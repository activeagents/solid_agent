# frozen_string_literal: true

# HasMemory gives an agent a persistent, agent-curated summary list — the
# model decides when to read and write it while interacting with tools,
# other agents, and users.
#
# Memory is scoped to a subject record (any ActiveRecord model) plus a
# scope name, NOT to the agent class — so a memory written by one agent can
# be recalled by another operating on the same subject. That makes it a
# handoff channel: agent A records what it learned/did, agent B picks the
# subject up and recalls the summary before continuing.
#
# The concern is duck-typed against a memory model exposing:
#   Model.for(memorable, scope:)  -> memory record
#   memory.remember(content, source_agent:, category:) -> entry
#   memory.recall(limit:, category:) -> entries (responding to #content)
# The install generator's AgentMemory implements this contract.
#
# @example Give an agent memory tools the model can call
#   class SupportAgent < ApplicationAgent
#     include SolidAgent::HasMemory
#     has_memory
#
#     def handle
#       prompt(message: params[:message], tools: memory_tool_definitions)
#     end
#   end
#
# @example Handoff between agents sharing a subject
#   ResearchAgent.with(memorable: project).research.generate_now
#   # later, a different agent class:
#   WriterAgent.with(memorable: project).draft.generate_now
#   # WriterAgent's recall_memory returns ResearchAgent's entries too.
module SolidAgent
  module HasMemory
    extend ActiveSupport::Concern

    DEFAULT_SCOPE = "default"

    # Function-calling schemas (common format) for the two memory tools.
    # Exposed as a module method so non-agent callers (platform executors,
    # MCP servers) can reuse the exact same contract.
    def self.tool_definitions
      [
        {
          name: "save_memory",
          description: "Persist a short summary note to long-term memory. Use for facts, decisions, task outcomes, or anything a future agent or session should know. Keep each note self-contained.",
          parameters: {
            type: "object",
            properties: {
              content: { type: "string", description: "The summary note to remember" },
              category: { type: "string", description: "Optional label, e.g. fact, task, handoff" }
            },
            required: [ "content" ]
          }
        },
        {
          name: "recall_memory",
          description: "Read back previously saved memory notes for the current subject, most recent first. Use before starting work to pick up prior context or another agent's handoff.",
          parameters: {
            type: "object",
            properties: {
              category: { type: "string", description: "Only return notes with this label" },
              limit: { type: "integer", description: "Maximum notes to return (default 20)" }
            },
            required: []
          }
        }
      ]
    end

    included do
      class_attribute :_memory_config, default: nil
    end

    class_methods do
      # Configures memory for this agent.
      #
      # @param scope [String, Symbol] memory namespace (default "default")
      # @param class_name [String] memory model (default "AgentMemory")
      def has_memory(scope: DEFAULT_SCOPE, class_name: "AgentMemory")
        self._memory_config = { scope: scope.to_s, class_name: class_name }
      end
    end

    # The memory record for the current subject (or nil without a subject).
    def memory
      config = self.class._memory_config || { scope: DEFAULT_SCOPE, class_name: "AgentMemory" }
      subject = memory_subject
      return nil unless subject

      @memory ||= config[:class_name].constantize.for(subject, scope: config[:scope])
    end

    # The record memory is attached to. Defaults to params[:memorable],
    # falling back to the HasContext contextable when present. Override for
    # custom subjects.
    def memory_subject
      return params[:memorable] if respond_to?(:params) && params.is_a?(Hash) && params[:memorable]

      context.contextable if respond_to?(:context) && context.respond_to?(:contextable)
    rescue StandardError
      nil
    end

    def memory_tool_definitions
      SolidAgent::HasMemory.tool_definitions
    end

    # Tool implementations — routed here by the provider's tool calls.

    def save_memory(content:, category: nil)
      return { error: "No memory subject available" } unless memory

      entry = memory.remember(content, source_agent: self.class.name, category: category)
      { saved: true, id: entry.respond_to?(:id) ? entry.id : nil, content: content }
    end

    def recall_memory(category: nil, limit: 20)
      return { error: "No memory subject available" } unless memory

      entries = memory.recall(limit: limit, category: category)
      {
        count: entries.size,
        entries: entries.map do |entry|
          {
            content: entry.content,
            category: (entry.category if entry.respond_to?(:category)),
            source_agent: (entry.source_agent if entry.respond_to?(:source_agent)),
            created_at: (entry.created_at.iso8601 if entry.respond_to?(:created_at) && entry.created_at)
          }.compact
        end
      }
    end
  end
end

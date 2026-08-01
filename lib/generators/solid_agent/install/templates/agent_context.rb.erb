# frozen_string_literal: true

# AgentContext stores conversation context for AI agents.
#
# Each context represents a single conversation or task session,
# tracking messages, generations, and metadata.
#
# @example Creating a context for a user
#   context = AgentContext.create!(
#     contextable: current_user,
#     agent_name: "WritingAssistantAgent",
#     action_name: "improve"
#   )
#
# @example Finding contexts for a record
#   user.agent_contexts.recent.each do |context|
#     puts "#{context.agent_name}##{context.action_name}: #{context.messages.count} messages"
#   end
#
class AgentContext < ApplicationRecord
  # Associations
  belongs_to :contextable, polymorphic: true, optional: true
  has_many :messages, class_name: "AgentMessage", dependent: :destroy
  has_many :generations, class_name: "AgentGeneration", dependent: :destroy

  # Validations
  validates :agent_name, presence: true
  validates :action_name, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(name) { where(agent_name: name) }
  scope :for_action, ->(name) { where(action_name: name) }
  scope :with_trace, ->(trace_id) { where(trace_id: trace_id) }

  # Convenience method to get input_params from options
  def input_params
    options&.dig("input_params") || options&.dig(:input_params) || {}
  end

  # Records a generation response and updates token counts
  #
  # Response attributes are read defensively: ActiveAgent 1.x response
  # objects don't expose #provider or #duration, and provider messages may
  # not respond to #tool_calls — a hard read would raise inside
  # SolidAgent's rescued persistence callback and silently drop the
  # generation.
  #
  # @param response [ActiveAgent::GenerationResponse] the generation response
  # @param extra_attributes [Hash] additional column values (e.g. trace_id, provenance)
  # @return [AgentGeneration] the created generation record
  def record_generation!(response, extra_attributes = {})
    usage = response.respond_to?(:usage) ? response.usage : nil

    generation = generations.create!({
      content: response.message&.content,
      model: response_value(response, :model),
      provider: response_value(response, :provider),
      finish_reason: response_value(response, :finish_reason),
      input_tokens: usage&.input_tokens || 0,
      output_tokens: usage&.output_tokens || 0,
      cached_tokens: response_value(usage, :cached_tokens) || 0,
      reasoning_tokens: response_value(usage, :reasoning_tokens) || 0,
      tool_calls: extract_tool_calls(response),
      raw_response: response_value(response, :raw_response),
      duration_seconds: extract_duration_seconds(response, usage)
    }.merge(extra_attributes))

    # Update cumulative token counts
    increment!(:total_input_tokens, generation.input_tokens)
    increment!(:total_output_tokens, generation.output_tokens)

    # Also add assistant message to the conversation
    add_assistant_message(response.message&.content, metadata: { "tool_calls" => generation.tool_calls })

    generation
  end

  # Records a generation together with its provenance snapshot, correlating
  # it with the distributed trace via provenance[:trace_id].
  #
  # Called automatically by SolidAgent::HasContext when this method exists.
  #
  # @param response [ActiveAgent::GenerationResponse] the generation response
  # @param provenance [Hash] provenance hash from HasContext#current_provenance
  # @return [AgentGeneration] the created generation record
  def record_generation_with_provenance!(response, provenance)
    provenance = (provenance || {}).deep_stringify_keys

    record_generation!(
      response,
      trace_id: provenance["trace_id"],
      provenance: provenance
    )
  end

  # Adds a user message to the context
  #
  # @param content [String] the message content
  # @param attributes [Hash] additional attributes
  # @return [AgentMessage] the created message
  def add_user_message(content, **attributes)
    messages.create!(role: "user", content: content, **attributes)
  end

  # Adds an assistant message to the context
  #
  # @param content [String] the message content
  # @param attributes [Hash] additional attributes
  # @return [AgentMessage] the created message
  def add_assistant_message(content, **attributes)
    messages.create!(role: "assistant", content: content, **attributes)
  end

  # Adds a system message to the context
  #
  # @param content [String] the message content
  # @return [AgentMessage] the created message
  def add_system_message(content)
    messages.create!(role: "system", content: content)
  end

  # Adds a tool result message to the context
  #
  # @param tool_call_id [String] the ID of the tool call
  # @param tool_name [String] the name of the tool
  # @param result [Hash, String] the tool result
  # @return [AgentMessage] the created message
  def add_tool_message(tool_call_id:, tool_name:, result:, arguments: nil, duration_ms: nil)
    messages.create!(
      role: "tool",
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      tool_result: result,
      tool_arguments: arguments.presence || {},
      metadata: duration_ms ? { "duration_ms" => duration_ms } : {},
      content: result.is_a?(String) ? result : result.to_json
    )
  end

  # Returns total token count
  def total_tokens
    total_input_tokens + total_output_tokens
  end

  private

  def response_value(response, method)
    response.respond_to?(method) ? response.public_send(method) : nil
  end

  def extract_duration_seconds(response, usage)
    return response.duration if response.respond_to?(:duration) && response.duration

    duration_ms = usage.respond_to?(:duration_ms) ? usage.duration_ms : nil
    duration_ms ? duration_ms / 1000.0 : nil
  end

  def extract_tool_calls(response)
    message = response.message
    return [] unless message.respond_to?(:tool_calls) && message.tool_calls.present?

    message.tool_calls.map do |tc|
      {
        id: tc.respond_to?(:id) ? tc.id : nil,
        name: tc.respond_to?(:name) ? tc.name : nil,
        arguments: tc.respond_to?(:arguments) ? tc.arguments : nil
      }
    end
  end
end

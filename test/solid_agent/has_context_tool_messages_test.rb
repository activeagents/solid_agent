# frozen_string_literal: true

require "test_helper"

# Tool-message persistence (HasContext#persist_tool_messages_to_context):
# tool results from the response's message stack land on the context,
# deduped by tool_call_id, enriched with the executor's own invocation
# records (arguments/timing) via the overridable tool_invocations hook.
#
# NOTE: test_helper stubs ActiveSupport::Concern and loads the full gem
# against it — do NOT require "active_support" here.
class HasContextToolMessagesTest < Minitest::Test
  FakeToolMessage = Struct.new(:role, :name, :tool_call_id, :content)

  class FakeResponse
    attr_reader :messages

    def initialize(messages)
      @messages = messages
    end
  end

  # Modern context: add_tool_message accepts the enrichment keywords.
  class FakeContext
    attr_reader :tool_messages

    def initialize(existing_tool_call_ids: [])
      @tool_messages = []
      @existing = existing_tool_call_ids
    end

    def add_tool_message(tool_call_id:, tool_name:, result:, arguments: nil, duration_ms: nil)
      @tool_messages << {
        tool_call_id: tool_call_id, tool_name: tool_name, result: result,
        arguments: arguments, duration_ms: duration_ms
      }
    end

    def messages
      existing = @existing
      scope = Object.new
      scope.define_singleton_method(:exists?) do |role:, tool_call_id:|
        existing.include?(tool_call_id)
      end
      scope
    end
  end

  # Legacy context generated before the enrichment keywords existed.
  class LegacyContext
    attr_reader :tool_messages

    def initialize
      @tool_messages = []
    end

    def add_tool_message(tool_call_id:, tool_name:, result:)
      @tool_messages << { tool_call_id: tool_call_id, tool_name: tool_name, result: result }
    end

    def messages
      scope = Object.new
      scope.define_singleton_method(:exists?) { |role:, tool_call_id:| false }
      scope
    end
  end

  def setup
    Object.const_set(:AgentContext, SolidAgentTestHelpers::MockAgentContext) unless defined?(AgentContext)
    Object.const_set(:AgentMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(AgentMessage)
    Object.const_set(:AgentGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(AgentGeneration)

    @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
      has_context
    end
  end

  def teardown
    Object.send(:remove_const, :AgentContext) if defined?(AgentContext)
    Object.send(:remove_const, :AgentMessage) if defined?(AgentMessage)
    Object.send(:remove_const, :AgentGeneration) if defined?(AgentGeneration)
  end

  def build_agent(context, response, invocations: nil)
    agent = @agent_class.new
    agent.context = context
    agent.generation_response = response
    agent.define_singleton_method(:tool_invocations) { invocations } if invocations
    agent
  end

  def test_persists_tool_messages_from_response_stack
    context = FakeContext.new
    response = FakeResponse.new([
      FakeToolMessage.new("assistant", nil, nil, "Let me check."),
      FakeToolMessage.new("tool", "calculate", "call_1", "42")
    ])

    build_agent(context, response).send(:persist_tool_messages_to_context)

    assert_equal 1, context.tool_messages.length
    message = context.tool_messages.first
    assert_equal "call_1", message[:tool_call_id]
    assert_equal "calculate", message[:tool_name]
    assert_equal "42", message[:result]
  end

  def test_enriches_from_tool_invocations_matched_by_tool_call_id
    context = FakeContext.new
    response = FakeResponse.new([
      FakeToolMessage.new("tool", "fetch_url", "call_9", "{\"body\":\"...\"}")
    ])
    invocations = [
      { tool_call_id: "call_9", name: "fetch_url", arguments: { "url" => "https://example.com" }, duration_ms: 120 }
    ]

    build_agent(context, response, invocations: invocations).send(:persist_tool_messages_to_context)

    message = context.tool_messages.first
    assert_equal({ "url" => "https://example.com" }, message[:arguments])
    assert_equal 120, message[:duration_ms]
  end

  def test_enriches_positionally_and_names_nameless_tool_messages
    # Ollama-style: tool messages carry no name and no tool_call_id.
    context = FakeContext.new
    response = FakeResponse.new([
      FakeToolMessage.new("tool", nil, nil, "42"),
      FakeToolMessage.new("tool", nil, nil, "cached")
    ])
    invocations = [
      { name: "calculate", arguments: { "expression" => "6*7" }, duration_ms: 3 },
      { name: "recall_memory", arguments: {}, duration_ms: 1 }
    ]

    build_agent(context, response, invocations: invocations).send(:persist_tool_messages_to_context)

    assert_equal %w[calculate recall_memory], context.tool_messages.map { |m| m[:tool_name] }
    assert_equal({ "expression" => "6*7" }, context.tool_messages.first[:arguments])
  end

  def test_skips_enrichment_keywords_for_legacy_contexts
    context = LegacyContext.new
    response = FakeResponse.new([ FakeToolMessage.new("tool", "calculate", "call_1", "42") ])
    invocations = [ { tool_call_id: "call_1", name: "calculate", arguments: { "expression" => "6*7" } } ]

    build_agent(context, response, invocations: invocations).send(:persist_tool_messages_to_context)

    assert_equal 1, context.tool_messages.length
    refute context.tool_messages.first.key?(:arguments)
  end

  def test_dedupes_by_tool_call_id
    context = FakeContext.new(existing_tool_call_ids: [ "call_1" ])
    response = FakeResponse.new([
      FakeToolMessage.new("tool", "calculate", "call_1", "42"),
      FakeToolMessage.new("tool", "fetch_url", "call_2", "ok")
    ])

    build_agent(context, response).send(:persist_tool_messages_to_context)

    assert_equal [ "call_2" ], context.tool_messages.map { |m| m[:tool_call_id] }
  end

  def test_skips_contexts_without_add_tool_message
    bare_context = Object.new
    response = FakeResponse.new([ FakeToolMessage.new("tool", "calculate", "call_1", "42") ])

    agent = build_agent(bare_context, response)
    agent.send(:persist_tool_messages_to_context)
    # Nothing raised, nothing persisted — the feature degrades silently.
  end
end

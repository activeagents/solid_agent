# frozen_string_literal: true

require "test_helper"

module SolidAgent
  class HasReasonsTest < Minitest::Test
    def setup
      @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
        include SolidAgent::HasReasons
      end

      @agent = @agent_class.new
    end

    def test_reasons_starts_empty
      assert_equal [], @agent.reasons
    end

    def test_has_reasoning_false_when_empty
      refute @agent.has_reasoning?
    end

    def test_capture_reasoning_from_response
      response = mock_reasoning_response(
        content: "Let me analyze this...",
        tokens: 150
      )

      reason = @agent.capture_reasoning(response)

      assert reason
      assert_equal "Let me analyze this...", reason.content
      assert_equal 150, reason.tokens
      assert_equal 1, @agent.reasons.count
    end

    def test_capture_reasoning_returns_nil_without_reasoning
      response = mock_reasoning_response(content: nil, tokens: 0)

      reason = @agent.capture_reasoning(response)

      assert_nil reason
      assert_equal 0, @agent.reasons.count
    end

    def test_last_reasoning
      @agent.capture_reasoning(mock_reasoning_response(content: "First", tokens: 50))
      @agent.capture_reasoning(mock_reasoning_response(content: "Second", tokens: 75))

      assert_equal "Second", @agent.last_reasoning.content
    end

    def test_total_reasoning_tokens
      @agent.capture_reasoning(mock_reasoning_response(content: "A", tokens: 50))
      @agent.capture_reasoning(mock_reasoning_response(content: "B", tokens: 75))
      @agent.capture_reasoning(mock_reasoning_response(content: "C", tokens: 100))

      assert_equal 225, @agent.total_reasoning_tokens
    end

    def test_has_reasoning_true_after_capture
      @agent.capture_reasoning(mock_reasoning_response(content: "Thinking", tokens: 50))

      assert @agent.has_reasoning?
    end

    def test_reasoning_chain
      @agent.capture_reasoning(mock_reasoning_response(content: "First thought", tokens: 50))
      @agent.capture_reasoning(mock_reasoning_response(content: "Second thought", tokens: 75))

      chain = @agent.reasoning_chain(separator: " | ")

      assert_equal "First thought | Second thought", chain
    end

    def test_reasoning_chain_excludes_redacted
      @agent.add_reason(content: "Visible", tokens: 50)
      @agent.add_reason(content: "[Redacted]", tokens: 75, redacted: true)
      @agent.add_reason(content: "Also visible", tokens: 60)

      chain = @agent.reasoning_chain(separator: " | ")

      assert_equal "Visible | Also visible", chain
    end

    def test_add_reason_manually
      reason = @agent.add_reason(
        content: "Manual reasoning",
        tokens: 100,
        thinking_time_ms: 500
      )

      assert_equal "Manual reasoning", reason.content
      assert_equal 100, reason.tokens
      assert_equal 1, @agent.reasons.count
    end

    def test_clear_reasons
      @agent.add_reason(content: "A", tokens: 50)
      @agent.add_reason(content: "B", tokens: 60)

      assert_equal 2, @agent.reasons.count

      @agent.clear_reasons!

      assert_equal 0, @agent.reasons.count
    end

    def test_reasoning_stats
      @agent.add_reason(content: "A", tokens: 50, thinking_time_ms: 100)
      @agent.add_reason(content: "B", tokens: 75, thinking_time_ms: 200)
      @agent.add_reason(content: "[Redacted]", tokens: 25, redacted: true)

      stats = @agent.reasoning_stats

      assert_equal 3, stats[:count]
      assert_equal 150, stats[:total_tokens]
      assert_equal 300, stats[:total_thinking_time_ms]
      assert_equal 1, stats[:redacted_count]
    end

    def test_has_reasons_class_config
      configured_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
        include SolidAgent::HasReasons
        has_reasons auto_capture: false, budget_tokens: 5000
      end

      config = configured_class._reasons_config

      assert_equal false, config[:auto_capture]
      assert_equal 5000, config[:budget_tokens]
    end

    def test_reasoning_prompt_options_with_budget
      configured_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
        include SolidAgent::HasReasons
        has_reasons budget_tokens: 10000
      end

      agent = configured_class.new
      options = agent.reasoning_prompt_options

      assert_equal 10000, options[:reasoning_budget_tokens]
    end

    private

    def mock_reasoning_response(content:, tokens:)
      MockReasoningResponse.new(content, tokens)
    end

    class MockReasoningResponse
      attr_reader :reasoning_content, :usage

      def initialize(content, tokens)
        @reasoning_content = content
        @usage = MockUsage.new(tokens)
      end

      def model
        "test-model"
      end

      class MockUsage
        attr_reader :reasoning_tokens

        def initialize(tokens)
          @reasoning_tokens = tokens
        end

        def thinking_time_ms
          nil
        end

        def reasoning_redacted
          false
        end

        def reasoning_budget_tokens
          nil
        end

        def reasoning_effort
          nil
        end
      end
    end
  end
end

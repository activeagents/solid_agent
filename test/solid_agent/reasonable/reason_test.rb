# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module Reasonable
    class ReasonTest < Minitest::Test
      def test_initialize_with_attributes
        reason = Reason.new(
          content: "Let me think about this...",
          tokens: 150,
          model: "claude-sonnet-4",
          thinking_time_ms: 2500
        )

        assert_equal "Let me think about this...", reason.content
        assert_equal 150, reason.tokens
        assert_equal "claude-sonnet-4", reason.model
        assert_equal 2500, reason.thinking_time_ms
        refute reason.redacted?
      end

      def test_extended_thinking_with_content
        reason = Reason.new(content: "Thinking...")

        assert reason.extended_thinking?
      end

      def test_extended_thinking_with_tokens
        reason = Reason.new(content: "", tokens: 100)

        assert reason.extended_thinking?
      end

      def test_not_extended_thinking_when_empty
        reason = Reason.new(content: "", tokens: 0)

        refute reason.extended_thinking?
      end

      def test_redacted
        reason = Reason.new(content: "[Redacted]", tokens: 100, redacted: true)

        assert reason.redacted?
        assert_equal "[Redacted]", reason.summary
      end

      def test_summary_truncates
        long_content = "A" * 500
        reason = Reason.new(content: long_content)

        summary = reason.summary(length: 100)

        assert summary.length <= 100
        assert summary.end_with?("...")
      end

      def test_to_h
        reason = Reason.new(
          content: "Thinking...",
          tokens: 50,
          model: "test-model",
          thinking_time_ms: 1000,
          metadata: { effort: "high" }
        )

        hash = reason.to_h

        assert_equal "Thinking...", hash[:content]
        assert_equal 50, hash[:tokens]
        assert_equal "test-model", hash[:model]
        assert_equal 1000, hash[:thinking_time_ms]
        assert_equal "high", hash[:metadata][:effort]
      end

      def test_from_h_with_string_keys
        hash = {
          "content" => "Reasoning content",
          "tokens" => 75,
          "model" => "claude"
        }

        reason = Reason.from_h(hash)

        assert_equal "Reasoning content", reason.content
        assert_equal 75, reason.tokens
        assert_equal "claude", reason.model
      end

      def test_from_h_with_symbol_keys
        hash = {
          content: "Reasoning content",
          tokens: 75,
          model: "claude"
        }

        reason = Reason.from_h(hash)

        assert_equal "Reasoning content", reason.content
        assert_equal 75, reason.tokens
      end

      def test_from_h_returns_nil_for_non_hash
        assert_nil Reason.from_h(nil)
        assert_nil Reason.from_h("not a hash")
        assert_nil Reason.from_h([])
      end

      def test_from_response_with_reasoning_content
        response = MockReasoningResponse.new(
          reasoning_content: "Step by step analysis...",
          reasoning_tokens: 200
        )

        reason = Reason.from_response(response)

        assert reason
        assert_equal "Step by step analysis...", reason.content
        assert_equal 200, reason.tokens
      end

      def test_from_response_returns_nil_without_reasoning
        response = MockReasoningResponse.new(
          reasoning_content: nil,
          reasoning_tokens: 0
        )

        reason = Reason.from_response(response)

        assert_nil reason
      end

      def test_from_response_with_nil
        assert_nil Reason.from_response(nil)
      end

      # Mock response class for testing
      class MockReasoningResponse
        attr_reader :reasoning_content, :model, :usage

        def initialize(reasoning_content: nil, reasoning_tokens: 0, model: nil)
          @reasoning_content = reasoning_content
          @model = model
          @usage = MockUsage.new(reasoning_tokens)
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
end

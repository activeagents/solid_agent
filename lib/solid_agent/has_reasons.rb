# frozen_string_literal: true

module SolidAgent
  # HasReasons provides reasoning/thinking trace collection for agents.
  #
  # This concern enables agents to capture and track extended thinking
  # from LLMs that support it (Claude's extended thinking, OpenAI o1, etc.).
  #
  # Reasoning traces are captured separately from the main response content,
  # allowing for:
  # - Transparent AI decision-making
  # - Debugging and analysis of AI behavior
  # - Audit trails for compliance
  # - Cost tracking (reasoning tokens)
  #
  # @example Basic usage
  #   class ResearchAgent < ApplicationAgent
  #     include SolidAgent::HasReasons
  #
  #     def analyze
  #       result = prompt(
  #         messages: research_messages,
  #         extended_thinking: true  # Enable extended thinking
  #       )
  #
  #       # Reasoning is automatically captured
  #       last_reasoning.content  #=> "Let me analyze this systematically..."
  #       total_reasoning_tokens  #=> 450
  #     end
  #   end
  #
  # @example Configuring reasoning capture
  #   class AnalysisAgent < ApplicationAgent
  #     include SolidAgent::HasReasons
  #
  #     has_reasons(
  #       auto_capture: true,        # Auto-capture from all generations
  #       persist: true,             # Persist to database
  #       budget_tokens: 10000       # Default reasoning token budget
  #     )
  #   end
  #
  # @example Accessing reasoning history
  #   agent.reasons                  # All captured reasons
  #   agent.reasoning_chain          # Formatted reasoning chain
  #   agent.total_reasoning_tokens   # Sum of all reasoning tokens
  #
  module HasReasons
    extend ActiveSupport::Concern

    included do
      class_attribute :_reasons_config, default: {
        auto_capture: true,
        persist: false,
        budget_tokens: nil,
        redact_on_persist: false
      }

      # Storage for captured reasons
      attr_accessor :_captured_reasons
    end

    class_methods do
      # Configure reasoning behavior for this agent
      #
      # @param auto_capture [Boolean] Automatically capture reasoning from responses
      # @param persist [Boolean] Persist reasoning to context (requires HasContext)
      # @param budget_tokens [Integer, nil] Default reasoning token budget
      # @param redact_on_persist [Boolean] Redact reasoning content when persisting
      def has_reasons(auto_capture: true, persist: false, budget_tokens: nil, redact_on_persist: false)
        self._reasons_config = {
          auto_capture: auto_capture,
          persist: persist,
          budget_tokens: budget_tokens,
          redact_on_persist: redact_on_persist
        }
      end
    end

    # Get all captured reasons for this agent instance
    #
    # @return [Array<Reasonable::Reason>]
    def reasons
      @_captured_reasons ||= []
    end

    # Get the last captured reason
    #
    # @return [Reasonable::Reason, nil]
    def last_reasoning
      reasons.last
    end

    # Get the total reasoning tokens used
    #
    # @return [Integer]
    def total_reasoning_tokens
      reasons.sum(&:tokens)
    end

    # Check if any reasoning has been captured
    #
    # @return [Boolean]
    def has_reasoning?
      reasons.any?(&:extended_thinking?)
    end

    # Get a formatted reasoning chain (all reasoning in sequence)
    #
    # @param separator [String] Separator between reasons
    # @return [String]
    def reasoning_chain(separator: "\n\n---\n\n")
      reasons
        .select(&:extended_thinking?)
        .reject(&:redacted?)
        .map(&:content)
        .join(separator)
    end

    # Get reasoning statistics
    #
    # @return [Hash]
    def reasoning_stats
      {
        count: reasons.count,
        total_tokens: total_reasoning_tokens,
        total_thinking_time_ms: reasons.sum { |r| r.thinking_time_ms || 0 },
        redacted_count: reasons.count(&:redacted?),
        models: reasons.map(&:model).compact.uniq
      }
    end

    # Capture reasoning from an LLM response
    #
    # @param response [Object] LLM response object
    # @return [Reasonable::Reason, nil] The captured reason
    def capture_reasoning(response)
      reason = Reasonable::Reason.from_response(response)
      return nil unless reason&.extended_thinking?

      @_captured_reasons ||= []
      @_captured_reasons << reason

      # Persist if configured and HasContext is available
      persist_reasoning(reason) if _reasons_config[:persist]

      reason
    end

    # Manually add a reason
    #
    # @param content [String] Reasoning content
    # @param tokens [Integer] Token count
    # @param metadata [Hash] Additional metadata
    # @return [Reasonable::Reason]
    def add_reason(content:, tokens: 0, **metadata)
      reason = Reasonable::Reason.new(
        content: content,
        tokens: tokens,
        model: current_model,
        **metadata
      )

      @_captured_reasons ||= []
      @_captured_reasons << reason

      persist_reasoning(reason) if _reasons_config[:persist]

      reason
    end

    # Clear all captured reasons
    def clear_reasons!
      @_captured_reasons = []
    end

    # Get default prompt options with reasoning configuration
    #
    # @return [Hash]
    def reasoning_prompt_options
      options = {}

      if _reasons_config[:budget_tokens]
        options[:reasoning_budget_tokens] = _reasons_config[:budget_tokens]
      end

      options[:extended_thinking] = true if _reasons_config[:auto_capture]

      options
    end

    private

    def persist_reasoning(reason)
      return unless respond_to?(:context) && context.respond_to?(:generations)

      # Find the most recent generation and store reasoning
      generation = context.generations.order(created_at: :desc).first
      return unless generation

      if generation.respond_to?(:store_reason!)
        # If generation includes Reasonable
        persisted_reason = if _reasons_config[:redact_on_persist]
          Reasonable::Reason.new(
            content: "[Redacted]",
            tokens: reason.tokens,
            model: reason.model,
            thinking_time_ms: reason.thinking_time_ms,
            redacted: true,
            metadata: reason.metadata
          )
        else
          reason
        end

        generation.store_reason!(persisted_reason)
      end
    rescue StandardError => e
      # Log but don't fail if persistence fails
      Rails.logger.warn "[SolidAgent::HasReasons] Failed to persist reasoning: #{e.message}" if defined?(Rails)
    end

    def current_model
      return @model if defined?(@model)
      return prompt_options[:model] if respond_to?(:prompt_options) && prompt_options[:model]

      nil
    end
  end
end

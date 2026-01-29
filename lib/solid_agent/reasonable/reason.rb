# frozen_string_literal: true

module SolidAgent
  module Reasonable
    # Reason represents a single reasoning trace from an LLM's extended thinking.
    #
    # LLMs like Claude (with extended thinking) and OpenAI's o1 models produce
    # reasoning traces that explain their thought process before generating output.
    # This class captures and structures that reasoning for persistence and analysis.
    #
    # @example Creating a reason from an LLM response
    #   reason = Reason.new(
    #     content: "Let me think about this step by step...",
    #     tokens: 150,
    #     model: "claude-sonnet-4-20250514",
    #     thinking_time_ms: 2500
    #   )
    #
    # @example Checking if reasoning was used
    #   reason.extended_thinking? #=> true
    #   reason.summary(100) #=> "Let me think about this..."
    #
    class Reason
      attr_reader :content, :tokens, :model, :thinking_time_ms,
                  :created_at, :metadata, :redacted

      # Initialize a new Reason
      #
      # @param content [String] The reasoning content/trace
      # @param tokens [Integer] Number of reasoning tokens used
      # @param model [String] The model that generated the reasoning
      # @param thinking_time_ms [Integer, nil] Time spent on reasoning
      # @param redacted [Boolean] Whether content was redacted by provider
      # @param metadata [Hash] Additional provider-specific metadata
      def initialize(content:, tokens: 0, model: nil, thinking_time_ms: nil,
                     redacted: false, metadata: {}, created_at: nil)
        @content = content
        @tokens = tokens.to_i
        @model = model
        @thinking_time_ms = thinking_time_ms
        @redacted = redacted
        @metadata = metadata || {}
        @created_at = created_at || Time.current
      end

      # Check if this represents extended thinking (vs. standard generation)
      #
      # @return [Boolean]
      def extended_thinking?
        tokens.positive? || content.present?
      end

      # Check if the reasoning content was redacted by the provider
      #
      # @return [Boolean]
      def redacted?
        @redacted == true
      end

      # Get a summary of the reasoning content
      #
      # @param length [Integer] Maximum length of summary
      # @return [String]
      def summary(length: 200)
        return "[Redacted]" if redacted?
        return "" if content.blank?

        str = content.to_s
        return str if str.length <= length

        "#{str[0, length - 3]}..."
      end

      # Convert to a hash for serialization
      #
      # @return [Hash]
      def to_h
        {
          content: content,
          tokens: tokens,
          model: model,
          thinking_time_ms: thinking_time_ms,
          redacted: redacted,
          metadata: metadata,
          created_at: created_at&.iso8601
        }.compact
      end

      # Create from a hash (deserialization)
      #
      # @param hash [Hash] Hash representation
      # @return [Reason]
      def self.from_h(hash)
        return nil unless hash.is_a?(Hash)

        new(
          content: hash[:content] || hash["content"],
          tokens: hash[:tokens] || hash["tokens"] || 0,
          model: hash[:model] || hash["model"],
          thinking_time_ms: hash[:thinking_time_ms] || hash["thinking_time_ms"],
          redacted: hash[:redacted] || hash["redacted"] || false,
          metadata: hash[:metadata] || hash["metadata"] || {},
          created_at: parse_time(hash[:created_at] || hash["created_at"])
        )
      end

      # Create from an ActiveAgent/LLM provider response
      #
      # @param response [Object] Provider response object
      # @return [Reason, nil]
      def self.from_response(response)
        return nil unless response

        # Handle different response formats
        reasoning_content = extract_reasoning_content(response)
        reasoning_tokens = extract_reasoning_tokens(response)

        return nil if reasoning_content.blank? && reasoning_tokens.zero?

        new(
          content: reasoning_content,
          tokens: reasoning_tokens,
          model: response.respond_to?(:model) ? response.model : nil,
          thinking_time_ms: extract_thinking_time(response),
          redacted: reasoning_redacted?(response),
          metadata: extract_reasoning_metadata(response)
        )
      end

      class << self
        private

        def parse_time(value)
          return nil unless value
          return value if value.is_a?(Time)

          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def extract_reasoning_content(response)
          # Claude format
          return response.reasoning_content if response.respond_to?(:reasoning_content)

          # OpenAI o1 format (reasoning is often in a separate field)
          if response.respond_to?(:choices) && response.choices&.first
            choice = response.choices.first
            return choice.reasoning if choice.respond_to?(:reasoning)
          end

          # Check usage for reasoning summary
          if response.respond_to?(:usage) && response.usage
            usage = response.usage
            return usage.reasoning_content if usage.respond_to?(:reasoning_content)
          end

          nil
        end

        def extract_reasoning_tokens(response)
          return 0 unless response.respond_to?(:usage) && response.usage

          usage = response.usage
          if usage.respond_to?(:reasoning_tokens)
            usage.reasoning_tokens || 0
          else
            0
          end
        end

        def extract_thinking_time(response)
          return nil unless response.respond_to?(:usage) && response.usage

          usage = response.usage
          # Some providers track thinking time separately
          if usage.respond_to?(:thinking_time_ms)
            usage.thinking_time_ms
          elsif usage.respond_to?(:reasoning_time_ms)
            usage.reasoning_time_ms
          end
        end

        def reasoning_redacted?(response)
          return false unless response.respond_to?(:usage) && response.usage

          usage = response.usage
          usage.respond_to?(:reasoning_redacted) && usage.reasoning_redacted == true
        end

        def extract_reasoning_metadata(response)
          metadata = {}

          if response.respond_to?(:usage) && response.usage
            usage = response.usage
            metadata[:budget_tokens] = usage.reasoning_budget_tokens if usage.respond_to?(:reasoning_budget_tokens)
            metadata[:effort] = usage.reasoning_effort if usage.respond_to?(:reasoning_effort)
          end

          metadata.compact
        end
      end
    end
  end
end

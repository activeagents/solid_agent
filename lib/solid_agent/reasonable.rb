# frozen_string_literal: true

require_relative "reasonable/reason"

module SolidAgent
  # Reasonable provides AI reasoning/thinking trace support for models.
  #
  # This concern enables models to track and store reasoning traces from
  # LLMs that support extended thinking (like Claude's extended thinking
  # or OpenAI's o1 reasoning models).
  #
  # Reasoning traces help with:
  # - Transparency: Understanding why an AI made certain decisions
  # - Debugging: Identifying issues in AI logic
  # - Auditing: Maintaining records of AI decision-making processes
  # - Learning: Improving prompts based on reasoning patterns
  #
  # @example Basic usage in a model
  #   class AgentGeneration < ApplicationRecord
  #     include SolidAgent::Reasonable
  #   end
  #
  #   generation.store_reasoning!(response)
  #   generation.reasoning_content     #=> "Let me think step by step..."
  #   generation.reasoning_tokens      #=> 150
  #   generation.has_reasoning?        #=> true
  #
  # @example Configuring reasoning storage
  #   class MyGeneration < ApplicationRecord
  #     include SolidAgent::Reasonable
  #
  #     reasonable_config(
  #       column: :thinking_trace,    # Custom column name
  #       tokens_column: :think_tokens,
  #       auto_extract: true          # Auto-extract from responses
  #     )
  #   end
  #
  module Reasonable
    extend ActiveSupport::Concern

    included do
      # Default configuration
      class_attribute :_reasonable_config, default: {
        column: :reasoning_content,
        tokens_column: :reasoning_tokens,
        metadata_column: :reasoning_metadata,
        auto_extract: false
      }
    end

    class_methods do
      # Configure reasoning storage options
      #
      # @param column [Symbol] Column to store reasoning content
      # @param tokens_column [Symbol] Column to store token count
      # @param metadata_column [Symbol] Column to store metadata (JSON)
      # @param auto_extract [Boolean] Auto-extract reasoning from responses
      def reasonable_config(column: nil, tokens_column: nil, metadata_column: nil, auto_extract: nil)
        config = _reasonable_config.dup
        config[:column] = column if column
        config[:tokens_column] = tokens_column if tokens_column
        config[:metadata_column] = metadata_column if metadata_column
        config[:auto_extract] = auto_extract unless auto_extract.nil?
        self._reasonable_config = config
      end
    end

    # Store reasoning from an LLM response
    #
    # @param response [Object] LLM response with reasoning data
    # @return [Reason, nil] The extracted reason or nil
    def store_reasoning!(response)
      reason = Reason.from_response(response)
      return nil unless reason&.extended_thinking?

      update_reasoning_columns(reason)
      reason
    end

    # Store reasoning from a Reason object
    #
    # @param reason [Reason] The reason to store
    # @return [Reason] The stored reason
    def store_reason!(reason)
      return nil unless reason.is_a?(Reason)

      update_reasoning_columns(reason)
      reason
    end

    # Get the stored reasoning content
    #
    # @return [String, nil]
    def reasoning_content
      column = _reasonable_config[:column]
      respond_to?(column) ? send(column) : nil
    end

    # Get the stored reasoning token count
    #
    # @return [Integer]
    def reasoning_tokens
      column = _reasonable_config[:tokens_column]
      (respond_to?(column) ? send(column) : 0).to_i
    end

    # Get the stored reasoning metadata
    #
    # @return [Hash]
    def reasoning_metadata
      column = _reasonable_config[:metadata_column]
      (respond_to?(column) ? send(column) : {}) || {}
    end

    # Check if this record has reasoning stored
    #
    # @return [Boolean]
    def has_reasoning?
      reasoning_content.present? || reasoning_tokens.positive?
    end

    # Check if reasoning was redacted
    #
    # @return [Boolean]
    def reasoning_redacted?
      reasoning_metadata["redacted"] == true
    end

    # Get a Reason object from stored data
    #
    # @return [Reason, nil]
    def to_reason
      return nil unless has_reasoning?

      Reason.new(
        content: reasoning_content,
        tokens: reasoning_tokens,
        model: respond_to?(:model) ? model : nil,
        thinking_time_ms: reasoning_metadata["thinking_time_ms"],
        redacted: reasoning_redacted?,
        metadata: reasoning_metadata,
        created_at: respond_to?(:created_at) ? created_at : nil
      )
    end

    # Get a summary of the reasoning
    #
    # @param length [Integer] Maximum length
    # @return [String]
    def reasoning_summary(length: 200)
      return "[Redacted]" if reasoning_redacted?
      return "" if reasoning_content.blank?

      reasoning_content.truncate(length)
    end

    private

    def update_reasoning_columns(reason)
      updates = {}

      content_col = _reasonable_config[:column]
      tokens_col = _reasonable_config[:tokens_column]
      metadata_col = _reasonable_config[:metadata_column]

      updates[content_col] = reason.content if respond_to?("#{content_col}=")
      updates[tokens_col] = reason.tokens if respond_to?("#{tokens_col}=")

      if respond_to?("#{metadata_col}=")
        updates[metadata_col] = {
          thinking_time_ms: reason.thinking_time_ms,
          redacted: reason.redacted,
          model: reason.model
        }.merge(reason.metadata).compact
      end

      update!(updates) if updates.any? && respond_to?(:update!)
    end
  end
end

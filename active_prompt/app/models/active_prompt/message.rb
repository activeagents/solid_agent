# frozen_string_literal: true

module ActivePrompt
  # Message represents a single message in a session conversation.
  #
  # Messages track the full conversation history between the user and agent,
  # including system messages, tool calls, and reasoning traces.
  #
  class Message < ApplicationRecord
    self.table_name = "active_prompt_messages"

    # Roles
    ROLES = %w[system user assistant tool].freeze

    # Associations
    belongs_to :session, class_name: "ActivePrompt::Session"

    # Validations
    validates :role, presence: true, inclusion: { in: ROLES }
    validates :content, presence: true, allow_blank: true

    # Serialized attributes
    serialize :tool_calls, coder: JSON
    serialize :metadata, coder: JSON

    # Scopes
    scope :ordered, -> { order(created_at: :asc) }
    scope :by_role, ->(role) { where(role: role) }
    scope :user_messages, -> { by_role("user") }
    scope :assistant_messages, -> { by_role("assistant") }
    scope :system_messages, -> { by_role("system") }
    scope :tool_messages, -> { by_role("tool") }

    # Callbacks
    before_create :set_defaults

    # Convert to format expected by LLM APIs
    #
    # @return [Hash]
    def to_message_hash
      hash = { role: role, content: content }
      hash[:tool_calls] = tool_calls if tool_calls.present?
      hash[:tool_call_id] = tool_call_id if tool_call_id.present?
      hash[:name] = name if name.present?
      hash
    end

    # Check if this is a user message
    #
    # @return [Boolean]
    def user?
      role == "user"
    end

    # Check if this is an assistant message
    #
    # @return [Boolean]
    def assistant?
      role == "assistant"
    end

    # Check if this is a system message
    #
    # @return [Boolean]
    def system?
      role == "system"
    end

    # Check if this is a tool message
    #
    # @return [Boolean]
    def tool?
      role == "tool"
    end

    # Check if this message has tool calls
    #
    # @return [Boolean]
    def has_tool_calls?
      tool_calls.present? && tool_calls.any?
    end

    # Get token count estimate
    #
    # @return [Integer]
    def estimated_tokens
      # Rough estimate: ~4 characters per token
      (content.to_s.length / 4.0).ceil
    end

    private

    def set_defaults
      self.metadata ||= {}
      self.tool_calls ||= []
    end
  end
end

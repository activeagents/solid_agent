# frozen_string_literal: true

# AgentMessage stores individual messages within an agent context.
#
# Messages can be from users, assistants, system prompts, or tool results.
# This provides a full audit trail of the conversation.
#
# @example Adding messages to a context
#   context.messages.create!(role: "user", content: "Hello!")
#   context.messages.create!(role: "assistant", content: "Hi there!")
#
# @example Tool call message
#   context.messages.create!(
#     role: "assistant",
#     content: nil,
#     tool_calls: [{ id: "call_123", name: "search", arguments: { query: "Ruby" } }]
#   )
#
# @example Tool result message
#   context.messages.create!(
#     role: "tool",
#     tool_call_id: "call_123",
#     tool_name: "search",
#     tool_result: { results: [...] }
#   )
#
class AgentMessage < ApplicationRecord
  # Associations
  belongs_to :agent_context

  # Validations
  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }

  # Scopes
  scope :by_role, ->(role) { where(role: role) }
  scope :user_messages, -> { by_role("user") }
  scope :assistant_messages, -> { by_role("assistant") }
  scope :system_messages, -> { by_role("system") }
  scope :tool_messages, -> { by_role("tool") }
  scope :chronological, -> { order(created_at: :asc) }

  # Converts the message to a hash format for ActiveAgent prompts
  #
  # @return [Hash] message in { role:, content: } format
  def to_message_hash
    hash = { role: role, content: content }

    # Include tool call info for assistant messages with tool calls
    if role == "assistant" && tool_calls_data.present?
      hash[:tool_calls] = tool_calls_data
    end

    # Include tool result info for tool messages
    if role == "tool"
      hash[:tool_call_id] = tool_call_id
      hash[:name] = tool_name
    end

    hash
  end

  # Returns parsed tool calls from metadata or dedicated columns
  def tool_calls_data
    metadata&.dig("tool_calls") || []
  end

  # Check if this is a tool call message
  def tool_call?
    role == "assistant" && tool_calls_data.present?
  end

  # Check if this is a tool result message
  def tool_result?
    role == "tool"
  end
end

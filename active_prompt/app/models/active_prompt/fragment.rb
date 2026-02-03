# frozen_string_literal: true

module ActivePrompt
  # Fragment represents a piece of cached context for session resumption.
  #
  # Fragments are the core mechanism for allowing agents to pause and resume
  # their work. They store intermediate state like browser snapshots, tool
  # outputs, reasoning traces, and other data needed to continue from
  # where the agent left off.
  #
  # @example Creating a fragment
  #   fragment = session.add_fragment(
  #     type: :browser_snapshot,
  #     content: { url: "https://example.com", dom_hash: "abc123" }
  #   )
  #
  # @example Restoring fragments
  #   fragments = session.fragments.by_type(:tool_output).ordered
  #   fragments.each { |f| agent.restore_context(f.content) }
  #
  class Fragment < ApplicationRecord
    self.table_name = "active_prompt_fragments"

    # Fragment types
    TYPES = {
      browser_state: "Browser state snapshot (URL, cookies, local storage)",
      browser_snapshot: "Full DOM snapshot for context",
      tool_output: "Output from a tool execution",
      reasoning: "AI reasoning/thinking trace",
      user_input: "User-provided input or decision",
      checkpoint: "General checkpoint for resumption",
      error: "Error state for debugging",
      authentication: "Authentication-related state",
      navigation: "Navigation history/breadcrumbs"
    }.freeze

    # Associations
    belongs_to :session, class_name: "ActivePrompt::Session"

    # Validations
    validates :fragment_type, presence: true, inclusion: { in: TYPES.keys.map(&:to_s) }
    validates :content, presence: true
    validates :sequence_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

    # Serialized attributes
    serialize :content, coder: JSON
    serialize :metadata, coder: JSON

    # Scopes
    scope :by_type, ->(type) { where(fragment_type: type.to_s) }
    scope :ordered, -> { order(sequence_number: :asc) }
    scope :recent, -> { order(created_at: :desc) }
    scope :since, ->(time) { where("created_at > ?", time) }
    scope :before, ->(time) { where("created_at < ?", time) }

    # Callbacks
    before_validation :set_defaults

    class << self
      # Create a browser state fragment
      #
      # @param session [Session] The session
      # @param url [String] Current URL
      # @param cookies [Hash] Browser cookies
      # @param local_storage [Hash] Local storage data
      # @param screenshot_path [String, nil] Optional screenshot path
      # @return [Fragment]
      def create_browser_state(session:, url:, cookies: {}, local_storage: {}, screenshot_path: nil)
        session.add_fragment(
          type: :browser_state,
          content: {
            url: url,
            cookies: cookies,
            local_storage: local_storage,
            screenshot_path: screenshot_path,
            captured_at: Time.current.iso8601
          }
        )
      end

      # Create a tool output fragment
      #
      # @param session [Session] The session
      # @param tool_name [String] Name of the tool
      # @param input [Hash] Tool input parameters
      # @param output [Hash, String] Tool output
      # @param duration_ms [Integer] Execution time
      # @return [Fragment]
      def create_tool_output(session:, tool_name:, input:, output:, duration_ms: nil)
        session.add_fragment(
          type: :tool_output,
          content: {
            tool_name: tool_name,
            input: input,
            output: output,
            duration_ms: duration_ms,
            executed_at: Time.current.iso8601
          }
        )
      end

      # Create a reasoning fragment
      #
      # @param session [Session] The session
      # @param reasoning [String] The reasoning content
      # @param tokens [Integer] Token count
      # @param model [String] Model that generated reasoning
      # @return [Fragment]
      def create_reasoning(session:, reasoning:, tokens: 0, model: nil)
        session.add_fragment(
          type: :reasoning,
          content: {
            reasoning: reasoning,
            tokens: tokens,
            model: model,
            created_at: Time.current.iso8601
          }
        )
      end

      # Create a checkpoint fragment
      #
      # @param session [Session] The session
      # @param label [String] Checkpoint label
      # @param data [Hash] Checkpoint data
      # @return [Fragment]
      def create_checkpoint(session:, label:, data: {})
        session.add_fragment(
          type: :checkpoint,
          content: data.merge(
            label: label,
            checkpoint_at: Time.current.iso8601
          )
        )
      end

      # Create an authentication fragment
      #
      # @param session [Session] The session
      # @param auth_type [Symbol] Type of auth (:login, :mfa, :oauth, :captcha)
      # @param target_url [String] URL requiring auth
      # @param instructions [String, nil] User instructions
      # @return [Fragment]
      def create_authentication(session:, auth_type:, target_url:, instructions: nil)
        session.add_fragment(
          type: :authentication,
          content: {
            auth_type: auth_type.to_s,
            target_url: target_url,
            instructions: instructions,
            requested_at: Time.current.iso8601
          }
        )
      end
    end

    # Check if this is a browser-related fragment
    #
    # @return [Boolean]
    def browser_fragment?
      %w[browser_state browser_snapshot].include?(fragment_type)
    end

    # Check if this fragment contains reasoning
    #
    # @return [Boolean]
    def reasoning_fragment?
      fragment_type == "reasoning"
    end

    # Get the age of this fragment
    #
    # @return [ActiveSupport::Duration]
    def age
      Time.current - created_at
    end

    # Check if fragment is stale (older than specified duration)
    #
    # @param max_age [ActiveSupport::Duration] Maximum age
    # @return [Boolean]
    def stale?(max_age = 1.hour)
      age > max_age
    end

    # Get a summary of this fragment
    #
    # @return [Hash]
    def summary
      {
        type: fragment_type,
        sequence: sequence_number,
        created_at: created_at,
        content_keys: content.is_a?(Hash) ? content.keys : [:raw],
        metadata: metadata
      }
    end

    # Convert to a format suitable for agent context
    #
    # @return [Hash]
    def to_context
      {
        type: fragment_type.to_sym,
        sequence: sequence_number,
        timestamp: created_at.iso8601,
        data: content
      }
    end

    private

    def set_defaults
      self.metadata ||= {}
      self.fragment_type = fragment_type.to_s if fragment_type.is_a?(Symbol)
    end
  end
end

# frozen_string_literal: true

module ActivePrompt
  # Session represents an active interaction session with an AI agent.
  #
  # Sessions track the conversation state, browser state (for Playwright agents),
  # and fragments that can be used to resume interrupted sessions.
  #
  # @example Creating a session
  #   session = ActivePrompt::Session.create!(
  #     prompt: prompt,
  #     user: current_user,
  #     state: :active
  #   )
  #
  # @example Resuming a session
  #   session = ActivePrompt::Session.find(session_id)
  #   session.resume! if session.paused?
  #
  class Session < ApplicationRecord
    self.table_name = "active_prompt_sessions"

    # States
    enum :state, {
      active: 0,
      paused: 1,
      waiting_for_auth: 2,
      waiting_for_user: 3,
      completed: 4,
      failed: 5,
      expired: 6
    }

    # Associations
    belongs_to :prompt, class_name: "ActivePrompt::Prompt"
    belongs_to :user, polymorphic: true, optional: true
    has_many :fragments, class_name: "ActivePrompt::Fragment", dependent: :destroy
    has_many :messages, class_name: "ActivePrompt::Message", dependent: :destroy

    # Serialized attributes
    serialize :metadata, coder: JSON
    serialize :browser_state, coder: JSON
    serialize :checkpoint_data, coder: JSON

    # Validations
    validates :state, presence: true

    # Callbacks
    before_create :set_defaults
    after_update :notify_state_change, if: :saved_change_to_state?

    # Scopes
    scope :active_sessions, -> { where(state: [:active, :paused, :waiting_for_auth, :waiting_for_user]) }
    scope :for_user, ->(user) { where(user: user) }
    scope :resumable, -> { where(state: [:paused, :waiting_for_auth, :waiting_for_user]) }
    scope :expired, -> { where("expires_at < ?", Time.current) }

    class << self
      # Find or create a session for a user and prompt
      #
      # @param prompt [Prompt] The prompt to use
      # @param user [Object, nil] Optional user
      # @return [Session]
      def find_or_create_for(prompt:, user: nil)
        existing = active_sessions.for_user(user).where(prompt: prompt).first
        return existing if existing

        create!(prompt: prompt, user: user, state: :active)
      end

      # Clean up expired sessions
      def cleanup_expired!
        expired.update_all(state: :expired)
      end
    end

    # Pause the session and save current state
    #
    # @param reason [Symbol] Reason for pausing (:auth, :user_input, :manual)
    # @param checkpoint [Hash] Optional checkpoint data
    # @return [Boolean]
    def pause!(reason: :manual, checkpoint: {})
      new_state = case reason
                  when :auth then :waiting_for_auth
                  when :user_input then :waiting_for_user
                  else :paused
                  end

      update!(
        state: new_state,
        checkpoint_data: checkpoint.merge(
          paused_at: Time.current,
          pause_reason: reason
        )
      )
    end

    # Resume a paused session
    #
    # @return [Boolean]
    def resume!
      return false unless resumable?

      update!(
        state: :active,
        checkpoint_data: checkpoint_data.merge(resumed_at: Time.current)
      )
    end

    # Check if session can be resumed
    #
    # @return [Boolean]
    def resumable?
      paused? || waiting_for_auth? || waiting_for_user?
    end

    # Mark session as complete
    #
    # @param result [Hash] Optional result data
    # @return [Boolean]
    def complete!(result: {})
      update!(
        state: :completed,
        completed_at: Time.current,
        checkpoint_data: checkpoint_data.merge(result: result)
      )
    end

    # Mark session as failed
    #
    # @param error [String, Exception] Error information
    # @return [Boolean]
    def fail!(error:)
      error_info = error.is_a?(Exception) ? { class: error.class.name, message: error.message } : { message: error.to_s }

      update!(
        state: :failed,
        checkpoint_data: checkpoint_data.merge(error: error_info, failed_at: Time.current)
      )
    end

    # Add a fragment to this session
    #
    # @param type [Symbol] Fragment type
    # @param content [Hash] Fragment content
    # @param metadata [Hash] Optional metadata
    # @return [Fragment]
    def add_fragment(type:, content:, metadata: {})
      fragments.create!(
        fragment_type: type,
        content: content,
        metadata: metadata,
        sequence_number: next_fragment_sequence
      )
    end

    # Get the latest fragment of a type
    #
    # @param type [Symbol] Fragment type
    # @return [Fragment, nil]
    def latest_fragment(type)
      fragments.by_type(type).ordered.last
    end

    # Add a message to this session
    #
    # @param role [String] Message role (user, assistant, system)
    # @param content [String] Message content
    # @return [Message]
    def add_message(role:, content:, **attributes)
      messages.create!(role: role, content: content, **attributes)
    end

    # Get conversation messages in format suitable for LLM
    #
    # @return [Array<Hash>]
    def conversation_messages
      messages.ordered.map(&:to_message_hash)
    end

    # Save browser state for later resumption
    #
    # @param state [Hash] Browser state data
    # @return [Boolean]
    def save_browser_state!(state)
      update!(browser_state: state)
      add_fragment(type: :browser_state, content: state)
    end

    # Restore browser state
    #
    # @return [Hash, nil]
    def restore_browser_state
      browser_state || latest_fragment(:browser_state)&.content
    end

    # Check if session has expired
    #
    # @return [Boolean]
    def expired?
      expires_at.present? && expires_at < Time.current
    end

    # Extend session expiration
    #
    # @param duration [ActiveSupport::Duration] Duration to extend by
    # @return [Boolean]
    def extend_expiration!(duration = nil)
      duration ||= ActivePrompt.configuration.session_timeout
      update!(expires_at: Time.current + duration)
    end

    # Get session duration
    #
    # @return [ActiveSupport::Duration]
    def duration
      end_time = completed_at || Time.current
      end_time - created_at
    end

    # Get fragment count by type
    #
    # @return [Hash]
    def fragment_counts
      fragments.group(:fragment_type).count
    end

    private

    def set_defaults
      self.metadata ||= {}
      self.browser_state ||= {}
      self.checkpoint_data ||= {}
      self.expires_at ||= Time.current + ActivePrompt.configuration.session_timeout
    end

    def notify_state_change
      callback = ActivePrompt.configuration.on_session_state_change
      callback&.call(self, state_before_last_save, state)
    end

    def next_fragment_sequence
      (fragments.maximum(:sequence_number) || 0) + 1
    end
  end
end

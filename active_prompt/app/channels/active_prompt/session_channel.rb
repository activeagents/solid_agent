# frozen_string_literal: true

module ActivePrompt
  class SessionChannel < ApplicationCable::Channel
    def subscribed
      session_id = params[:session_id]
      stream_from "active_prompt:session:#{session_id}"
    end

    def unsubscribed
      # Cleanup when channel is unsubscribed
    end

    # Receive messages from the client (e.g., user completing auth)
    def receive(data)
      session_id = params[:session_id]
      session = Session.find(session_id)

      case data["type"]
      when "auth_complete"
        handle_auth_complete(session)
      when "user_input"
        handle_user_input(session, data["input"])
      when "cancel"
        handle_cancel(session)
      end
    end

    private

    def handle_auth_complete(session)
      return unless session.waiting_for_auth?

      Fragment.create_checkpoint(
        session: session,
        label: "auth_complete",
        data: { completed_at: Time.current.iso8601 }
      )

      session.resume!

      # Notify that auth is complete
      ActionCable.server.broadcast(
        "active_prompt:session:#{session.id}",
        type: "auth_complete",
        message: "Authentication complete. Resuming task..."
      )

      # Queue job to continue execution
      BrowserExecutionJob.perform_later(
        session.id,
        session.metadata["instructions"]
      )
    end

    def handle_user_input(session, input)
      return unless session.waiting_for_user?

      # Store user input as fragment
      session.add_fragment(
        type: :user_input,
        content: { input: input, provided_at: Time.current.iso8601 }
      )

      session.resume!

      # Notify and continue
      ActionCable.server.broadcast(
        "active_prompt:session:#{session.id}",
        type: "user_input_received",
        message: "Input received. Continuing..."
      )

      BrowserExecutionJob.perform_later(
        session.id,
        session.metadata["instructions"]
      )
    end

    def handle_cancel(session)
      session.fail!(error: "Cancelled by user")

      ActionCable.server.broadcast(
        "active_prompt:session:#{session.id}",
        type: "cancelled",
        message: "Task cancelled"
      )
    end
  end
end

# frozen_string_literal: true

module ActivePrompt
  class SessionsController < ApplicationController
    before_action :set_session, only: [:show, :pause, :resume, :complete, :fragments, :messages, :add_message]

    # GET /active_prompt/sessions
    def index
      @sessions = Session.includes(:prompt).order(created_at: :desc)
      @sessions = @sessions.for_user(current_user) if params[:user_only] && current_user

      render json: @sessions.map { |s| session_json(s) }
    end

    # GET /active_prompt/sessions/active
    def active
      @sessions = Session.active_sessions.includes(:prompt).order(created_at: :desc)
      @sessions = @sessions.for_user(current_user) if current_user

      render json: @sessions.map { |s| session_json(s) }
    end

    # GET /active_prompt/sessions/resumable
    def resumable
      @sessions = Session.resumable.includes(:prompt).order(created_at: :desc)
      @sessions = @sessions.for_user(current_user) if current_user

      render json: @sessions.map { |s| session_json(s) }
    end

    # GET /active_prompt/sessions/:id
    def show
      render json: session_json(@session, detailed: true)
    end

    # POST /active_prompt/sessions
    def create
      prompt = Prompt.find(params[:prompt_id])
      @session = prompt.create_session(
        user: current_user,
        metadata: params[:metadata]&.to_unsafe_h || {}
      )

      render json: session_json(@session), status: :created
    end

    # POST /active_prompt/sessions/:id/pause
    def pause
      reason = params[:reason]&.to_sym || :manual
      checkpoint = params[:checkpoint]&.to_unsafe_h || {}

      @session.pause!(reason: reason, checkpoint: checkpoint)

      render json: session_json(@session)
    end

    # POST /active_prompt/sessions/:id/resume
    def resume
      unless @session.resumable?
        render json: { error: "Session cannot be resumed" }, status: :unprocessable_entity
        return
      end

      @session.resume!
      render json: session_json(@session)
    end

    # POST /active_prompt/sessions/:id/complete
    def complete
      result = params[:result]&.to_unsafe_h || {}
      @session.complete!(result: result)

      render json: session_json(@session)
    end

    # GET /active_prompt/sessions/:id/fragments
    def fragments
      fragments = @session.fragments.ordered
      fragments = fragments.by_type(params[:type]) if params[:type]

      render json: fragments.map { |f| fragment_json(f) }
    end

    # GET /active_prompt/sessions/:id/messages
    def messages
      messages = @session.messages.ordered
      messages = messages.by_role(params[:role]) if params[:role]

      render json: messages.map(&:to_message_hash)
    end

    # POST /active_prompt/sessions/:id/add_message
    def add_message
      message = @session.add_message(
        role: params.require(:role),
        content: params.require(:content),
        tool_calls: params[:tool_calls],
        tool_call_id: params[:tool_call_id],
        name: params[:name]
      )

      render json: message.to_message_hash, status: :created
    end

    # DELETE /active_prompt/sessions/cleanup_expired
    def cleanup_expired
      count = Session.expired.count
      Session.cleanup_expired!

      render json: { cleaned_up: count }
    end

    private

    def set_session
      @session = Session.find(params[:id])
    end

    def session_json(session, detailed: false)
      json = {
        id: session.id,
        prompt_id: session.prompt_id,
        prompt_name: session.prompt.name,
        prompt_version: session.prompt.version,
        state: session.state,
        created_at: session.created_at,
        expires_at: session.expires_at,
        resumable: session.resumable?
      }

      if detailed
        json.merge!(
          metadata: session.metadata,
          browser_state: session.browser_state,
          checkpoint_data: session.checkpoint_data,
          fragment_counts: session.fragment_counts,
          message_count: session.messages.count,
          duration: session.duration.to_i
        )
      end

      json
    end

    def fragment_json(fragment)
      {
        id: fragment.id,
        type: fragment.fragment_type,
        sequence: fragment.sequence_number,
        created_at: fragment.created_at,
        content_preview: fragment.content.is_a?(Hash) ? fragment.content.keys : :raw,
        metadata: fragment.metadata
      }
    end
  end
end

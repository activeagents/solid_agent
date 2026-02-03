# frozen_string_literal: true

module ActivePrompt
  module Browser
    class AgentController < ApplicationController
      skip_before_action :verify_authenticity_token, only: [:execute, :resume, :auth_complete]

      # POST /active_prompt/browser/execute
      # Execute a browser automation task
      #
      # @param instructions [String] Simple one-liner instructions
      # @param prompt_name [String] Optional prompt name to use
      # @param prompt_version [String] Optional prompt version
      def execute
        instructions = params.require(:instructions)
        prompt_name = params[:prompt_name] || "browser-assistant"
        prompt_version = params[:prompt_version]

        # Find or create the prompt
        prompt = if prompt_version
                   Prompt.find_version(prompt_name, prompt_version)
                 else
                   Prompt.latest(prompt_name) || create_default_browser_prompt
                 end

        # Create a new session
        session = prompt.create_session(
          user: current_user,
          metadata: {
            instructions: instructions,
            started_at: Time.current.iso8601
          }
        )

        # Execute asynchronously or synchronously based on params
        if params[:async]
          BrowserExecutionJob.perform_later(session.id, instructions)
          render json: {
            status: :queued,
            session_id: session.id,
            message: "Task queued for execution"
          }
        else
          result = execute_browser_task(session, instructions)
          render json: result
        end
      end

      # POST /active_prompt/browser/resume
      # Resume a paused session
      #
      # @param session_id [Integer] Session to resume
      def resume
        session = Session.find(params.require(:session_id))

        unless session.resumable?
          render json: { error: "Session cannot be resumed", state: session.state }, status: :unprocessable_entity
          return
        end

        session.resume!

        # Continue execution
        result = execute_browser_task(session, session.metadata["instructions"])
        render json: result
      end

      # GET /active_prompt/browser/status
      # Get status of a session
      #
      # @param session_id [Integer] Session to check
      def status
        session = Session.find(params.require(:session_id))

        render json: {
          session_id: session.id,
          state: session.state,
          prompt_name: session.prompt.name,
          prompt_version: session.prompt.version,
          created_at: session.created_at,
          expires_at: session.expires_at,
          fragment_counts: session.fragment_counts,
          message_count: session.messages.count,
          checkpoint_data: session.checkpoint_data,
          browser_state: session.browser_state&.slice(:url, :title)
        }
      end

      # POST /active_prompt/browser/auth_complete
      # Signal that authentication is complete
      #
      # @param session_id [Integer] Session that was waiting for auth
      def auth_complete
        session = Session.find(params.require(:session_id))

        unless session.waiting_for_auth?
          render json: { error: "Session is not waiting for authentication" }, status: :unprocessable_entity
          return
        end

        # Create auth completion fragment
        Fragment.create_checkpoint(
          session: session,
          label: "auth_complete",
          data: {
            completed_at: Time.current.iso8601,
            auth_type: session.checkpoint_data["auth_type"]
          }
        )

        # Resume the session
        session.resume!

        # Continue execution
        result = execute_browser_task(session, session.metadata["instructions"])
        render json: result
      end

      private

      def execute_browser_task(session, instructions)
        # Build the agent
        agent_class = build_browser_agent_class(session.prompt)
        agent = agent_class.new(
          task_instructions: instructions,
          session: session,
          params: {
            stream_id: params[:stream_id]
          }
        )

        # Execute
        result = agent.execute_with_session(
          user: current_user,
          resume_session_id: session.id
        )

        # Format response
        {
          status: result[:status],
          session_id: session.id,
          result: result[:result],
          message: status_message(result[:status]),
          execution_log: result[:execution_log],
          can_resume: session.reload.resumable?
        }
      rescue StandardError => e
        Rails.logger.error("[BrowserAgent] Error: #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n"))

        {
          status: :error,
          session_id: session.id,
          error: e.message
        }
      end

      def build_browser_agent_class(prompt)
        # Build a dynamic agent class from the prompt
        Class.new do
          include ActivePrompt::BrowserAgent

          define_method(:initialize) do |params = {}|
            @task_instructions = params[:task_instructions]
            @session = params[:session]
            @params = params[:params] || {}
            initialize_browser_session
          end

          # Override to use the session's context
          define_method(:session) { @session }
        end
      end

      def create_default_browser_prompt
        Prompt.create!(
          name: "browser-assistant",
          version: "1.0.0",
          model: ActivePrompt.configuration.default_model,
          instructions: default_instructions,
          tools: BrowserAgent::PLAYWRIGHT_TOOLS.map { |t| { name: t } }
        )
      end

      def default_instructions
        <<~INSTRUCTIONS
          You are a browser automation assistant. Execute tasks by navigating web pages,
          interacting with elements, and extracting information.

          When you encounter login pages or authentication requirements, stop and wait
          for the user to complete authentication.
        INSTRUCTIONS
      end

      def status_message(status)
        case status.to_sym
        when :completed
          "Task completed successfully"
        when :waiting_for_auth
          "Authentication required. Please log in and signal when complete."
        when :waiting_for_user
          "Waiting for user input"
        when :failed
          "Task failed"
        else
          "Task in progress"
        end
      end
    end
  end
end

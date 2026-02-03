# frozen_string_literal: true

module ActivePrompt
  class BrowserExecutionJob < ApplicationJob
    queue_as :default

    def perform(session_id, instructions)
      session = Session.find(session_id)

      # Build the agent class dynamically
      agent = build_agent(session, instructions)

      # Execute the task
      result = agent.execute_with_session(resume_session_id: session_id)

      # Broadcast result
      broadcast_result(session, result)

      result
    rescue StandardError => e
      Rails.logger.error("[BrowserExecutionJob] Error: #{e.message}")
      session.fail!(error: e) if session

      broadcast_error(session, e)
    end

    private

    def build_agent(session, instructions)
      agent_class = Class.new do
        include ActivePrompt::BrowserAgent

        define_method(:initialize) do |params = {}|
          @task_instructions = params[:task_instructions]
          @session = params[:session]
          initialize_browser_session
        end

        define_method(:session) { @session }
      end

      agent_class.new(
        task_instructions: instructions,
        session: session
      )
    end

    def broadcast_result(session, result)
      return unless defined?(ActionCable)

      ActionCable.server.broadcast(
        "active_prompt:session:#{session.id}",
        type: "result",
        status: result[:status],
        result: result[:result],
        can_resume: session.reload.resumable?
      )
    end

    def broadcast_error(session, error)
      return unless defined?(ActionCable) && session

      ActionCable.server.broadcast(
        "active_prompt:session:#{session.id}",
        type: "error",
        error: error.message
      )
    end
  end
end

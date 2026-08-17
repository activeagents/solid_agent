# frozen_string_literal: true

# The polling endpoint the progress stream exists for. Events are appended
# with update_column from the run's own thread, so a request mid-run reads
# whatever has landed so far.
class AgentRunsController < ApplicationController
  def create
    document = Document.find(params[:document_id])

    run = AgentRun.create!(
      runnable: document,
      agent_name: "ReportAgent",
      action_name: "analyze",
      input_prompt: params[:question]
    )

    DocumentAnalysisJob.perform_later(run.id)

    render json: { id: run.id, status: run.status }, status: :accepted
  end

  def show
    run = AgentRun.find(params[:id])

    render json: {
      status: run.status,
      in_progress: run.in_progress?,
      events: run.events,
      output: run.output,
      error: run.error_message,
      tokens: run.total_tokens,
      duration_ms: run.calculated_duration_ms(fallback_end: Time.current)
    }
  end

  def destroy
    run = AgentRun.find(params[:id])

    # Returns false when the run already finished — cancellation is a
    # request, not a guarantee.
    render json: { cancelled: run.cancel! }
  end
end

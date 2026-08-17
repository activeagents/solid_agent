# frozen_string_literal: true

# Runs exist because the work happens somewhere the request can't watch.
class DocumentAnalysisJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = AgentRun.find(run_id)
    return if run.finished? # cancelled before a worker picked it up

    DocumentAnalysisRun.new(run).call
  rescue StandardError
    # The service already recorded the failure on the run; re-raising lets
    # Active Job apply its own retry policy.
    raise
  end
end

# frozen_string_literal: true

# The agent the run records. Two details matter for run tracking:
#
# - the instructions are a constant, so the executor can fingerprint the
#   exact text a run executed under (see DocumentAnalysisRun),
# - the caller's trace id is threaded into prompt_options, so the
#   generation row, the context row and the run all carry the same
#   trace_id and can be joined with your telemetry.
#
# Docs: https://docs.activeagents.ai/solid_agent/runs
class ReportAgent < ApplicationAgent
  include SolidAgent::HasContext

  INSTRUCTIONS = <<~TEXT.freeze
    You are a document analyst. Answer only from the document you are given,
    quote the clause you are relying on, and say plainly when the document
    does not cover the question.
  TEXT

  generate_with :openai, model: "gpt-4o-mini"

  has_context contextual: :document

  def analyze
    prompt_options[:trace_id] = params[:trace_id] if params[:trace_id]

    prompt instructions: INSTRUCTIONS, message: params[:question]
  end
end

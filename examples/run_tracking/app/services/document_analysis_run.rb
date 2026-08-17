# frozen_string_literal: true

# A durable record of one agent execution.
#
# AgentRun is the row a background job writes so a UI has something to
# poll: lifecycle status, the input, the output, token and duration
# accounting, an append-only progress stream, and an instructions
# fingerprint that groups runs into cohorts when you change the prompt.
#
# Nothing in SolidAgent creates these for you — the executor does, which is
# what this service is. It takes a run that already exists (the controller
# creates it so the client has an id to poll immediately) and drives it
# through its lifecycle.
#
# Docs: https://docs.activeagents.ai/solid_agent/runs
class DocumentAnalysisRun
  def initialize(run)
    @run = run
    @document = run.runnable
    @question = run.input_prompt
  end

  def call
    # Fingerprint the instructions this run executed under. Runs sharing a
    # digest are one cohort — that is how "did the new prompt help?"
    # becomes a comparable question.
    @run.record_instructions(ReportAgent::INSTRUCTIONS)
    @run.trace_id ||= SecureRandom.uuid
    @run.save!
    @run.start!

    # Progress events pair up by eid: "started" stays pending in the UI
    # until a "done" or "error" with the same eid lands.
    @run.append_event(kind: "llm", label: "analyze", eid: "gen-1", status: "started")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = ReportAgent.with(
      document: @document,
      question: @question,
      trace_id: @run.trace_id
    ).analyze.generate_now

    @run.append_event(
      kind: "llm", label: "analyze", eid: "gen-1", status: "done",
      duration_ms: elapsed_ms(started)
    )

    @run.complete!(
      output: response.message.content,
      input_tokens: response.usage&.input_tokens,
      output_tokens: response.usage&.output_tokens,
      metadata: { model: "gpt-4o-mini" }
    )

    @run
  rescue StandardError => e
    # fail! records the message, stamps completed_at, computes duration.
    @run.append_event(kind: "llm", label: "analyze", eid: "gen-1", status: "error", detail: e.message)
    @run.fail!(e)
    raise
  end

  private

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end

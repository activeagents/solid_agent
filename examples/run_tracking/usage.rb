# frozen_string_literal: true

# Runs, cohorts and cost — rails console walkthrough.
#
# Docs: https://docs.activeagents.ai/solid_agent/runs

document = Document.find(1)

# The controller creates the row so the client has an id to poll; here we
# do both halves in one go.
run = AgentRun.create!(
  runnable: document,
  agent_name: "ReportAgent",
  action_name: "analyze",
  input_prompt: "Who owns the IP?"
)

DocumentAnalysisRun.new(run).call

run.status          # => "complete"
run.finished?       # => true
run.total_tokens
run.duration_ms
run.output

# The progress stream, oldest first. Each event is
# { at, eid, kind, label, status, detail, duration_ms }.
run.events
# => [{"at" => "2026-08-14T12:00:00.123Z", "eid" => "gen-1", "kind" => "llm",
#      "label" => "analyze", "status" => "started"},
#     {"at" => "...", "eid" => "gen-1", "kind" => "llm", "label" => "analyze",
#      "status" => "done", "duration_ms" => 1840}]

# --- Cohorts ------------------------------------------------------------

# Runs are grouped by the instructions they executed under. The digest is
# stable; the codename is the readable form of the same value.
run.instructions_digest    # => "a1b2c3d4"
run.instructions_codename  # => "calm-heron"

AgentRun.where(instructions_digest: run.instructions_digest).count

# "Did the new instructions help?" — one row per cohort.
AgentRun.for_agent("ReportAgent").where(status: "complete")
  .group(:instructions_digest)
  .average(:duration_ms)
  .transform_keys { |digest| SolidAgent::RunFingerprint.codename(digest) }
# => { "calm-heron" => 2400.0, "misty-atoll" => 1810.0 }

# Fingerprinting without a run record:
SolidAgent::RunFingerprint.digest(ReportAgent::INSTRUCTIONS)
SolidAgent::RunFingerprint.codename("a1b2c3d4")

# --- Scopes and correlation --------------------------------------------

AgentRun.recent.limit(20)
AgentRun.for_agent("ReportAgent").for_status("failed")
AgentRun.with_trace(run.trace_id)
AgentContext.with_trace(run.trace_id)
AgentGeneration.with_trace(run.trace_id)

# --- Cost ---------------------------------------------------------------

# Token counts are recorded; pricing is layered on top, so every figure is
# an estimate. Rates come from RubyLLM's registry when that gem is loaded
# and knows the model, and from a static pattern table otherwise.
SolidAgent::ModelPricing.estimate(
  model: "claude-sonnet-5", input_tokens: 12_000, output_tokens: 800
)
# => 0.048

SolidAgent::ModelPricing.rate_for("gpt-4o-mini") # => [0.15, 0.6] per 1M tokens

# The generated AgentGeneration#estimated_cost uses it automatically, and
# takes explicit rates when you have negotiated your own.
AgentGeneration.recent.first.estimated_cost
AgentGeneration.recent.first.estimated_cost(
  input_price_per_million: 0.10, output_price_per_million: 0.40
)

# Spend for a day, by model. Pricing is per-model, so total it in Ruby
# rather than in SQL:
AgentGeneration.where(created_at: 1.day.ago..)
  .group_by(&:model)
  .transform_values { |generations| generations.sum { |g| g.estimated_cost.to_f }.round(4) }

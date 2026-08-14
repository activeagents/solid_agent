# frozen_string_literal: true

require_relative "records_helper"

# The default-named host models this suite drives — Agent, AgentRun and
# Assistant — come from records_helper.rb. They carry the names SolidAgent
# falls back to, so the version suite needs the same constants and only one
# definition of each may exist; see the note above them there.

# Something to hang a polymorphic runnable off that is plainly not an agent.
class Workflow < ApplicationRecord
  self.table_name = "users"
end

# The two schemas the concern has to straddle, as they exist on real tables.
# Neither is the reconciled shape the harness defines: the platform table has
# `logs` and `total_tokens` but no `runnable` or `instructions_digest`, and the
# gem's earlier generator table has the reverse. Including the concern on both
# is the compatibility claim, so both are exercised.
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :platform_agent_runs, force: true do |t|
    t.references :agent
    t.string   :action_name
    t.string   :trace_id
    t.integer  :status, default: 0, null: false
    t.text     :input_prompt
    t.json     :input_params, default: {}
    t.text     :output
    t.json     :output_metadata, default: {}
    t.text     :error_message
    t.text     :error_backtrace
    t.json     :logs, default: []
    t.integer  :input_tokens
    t.integer  :output_tokens
    t.integer  :total_tokens
    t.integer  :duration_ms
    t.datetime :started_at
    t.datetime :completed_at
    t.timestamps
  end

  create_table :legacy_agent_runs, force: true do |t|
    t.references :runnable, polymorphic: true
    t.string   :agent_name
    t.string   :action_name
    t.string   :trace_id
    t.integer  :status, default: 0, null: false
    t.text     :input_prompt
    t.text     :output
    t.json     :output_metadata, default: {}
    t.text     :error_message
    t.json     :events, default: []
    t.string   :instructions_digest
    t.integer  :input_tokens
    t.integer  :output_tokens
    t.integer  :duration_ms
    t.datetime :started_at
    t.datetime :completed_at
    t.timestamps
  end
end

class PlatformRun < ApplicationRecord
  self.table_name = "platform_agent_runs"
  include SolidAgent::Records::AgentRun
  self.events_column = :logs
end

class LegacyRun < ApplicationRecord
  self.table_name = "legacy_agent_runs"
  include SolidAgent::Records::AgentRun
end

# events_column names a column this table does not have — the misconfiguration
# the checked accessor is there to report.
class MisconfiguredRun < ApplicationRecord
  self.table_name = "agent_runs"
  include SolidAgent::Records::AgentRun
  self.events_column = :logs
end

# A second run model under a different name, to prove the association is built
# from SolidAgent.agent_class rather than a hardcoded "Agent".
SolidAgent.agent_class = "Assistant"

class AssistantRun < ApplicationRecord
  self.table_name = "agent_runs"
  include SolidAgent::Records::AgentRun
end

SolidAgent.reset_records_configuration!

# after_commit callbacks do not fire inside a joinable transaction: an inner
# save just joins it and defers its callbacks to a commit that never comes.
# Rails' own transactional tests solve this by opening the wrapper as
# non-joinable, which makes each inner save a savepoint whose commit callbacks
# run immediately. RecordsTestCase's wrapper is joinable, so this replaces it
# rather than nesting inside it — hence binding ActiveSupport::TestCase#run
# instead of calling super.
class AgentRunTestCase < RecordsTestCase
  def run(*args, &block)
    result = nil
    ActiveRecord::Base.transaction(joinable: false) do
      result = ActiveSupport::TestCase.instance_method(:run).bind_call(self, *args, &block)
      raise ActiveRecord::Rollback
    end
    result
  end
end

class SolidAgentRecordsAgentRunTest < AgentRunTestCase
  def setup
    @agent = Agent.create!(name: "Support", slug: "support")
  end

  # --- status lifecycle ---------------------------------------------------

  test "status is an integer enum with the deployed numbering" do
    assert_equal({ "pending" => 0, "running" => 1, "complete" => 2, "failed" => 3, "cancelled" => 4 },
                 AgentRun.statuses)

    run = create_run(status: :complete)
    stored = AgentRun.connection.select_value("SELECT status FROM agent_runs WHERE id = #{run.id}")

    assert_equal 2, stored, "the column has to stay integer-backed"
  end

  test "a new run is pending and in progress" do
    run = create_run

    assert run.pending?
    assert run.in_progress?
    assert_not run.finished?
  end

  test "in_progress? and finished? partition every status" do
    in_progress = %i[pending running]
    finished = %i[complete failed cancelled]

    in_progress.each do |status|
      run = create_run(status: status)
      assert run.in_progress?, "#{status} should be in progress"
      assert_not run.finished?, "#{status} should not be finished"
    end

    finished.each do |status|
      run = create_run(status: status)
      assert_not run.in_progress?, "#{status} should not be in progress"
      assert run.finished?, "#{status} should be finished"
    end

    assert_equal AgentRun.statuses.keys.sort, (in_progress + finished).map(&:to_s).sort
  end

  test "start! moves the run to running and stamps started_at" do
    run = create_run

    run.start!

    assert run.reload.running?
    assert_not_nil run.started_at
  end

  test "finish! records output, usage, completion time and duration" do
    run = create_run(status: :running, started_at: 2.seconds.ago)

    run.finish!(output: "the answer", input_tokens: 120, output_tokens: 40)
    run.reload

    assert run.complete?
    assert_equal "the answer", run.output
    assert_equal 120, run.input_tokens
    assert_equal 40, run.output_tokens
    assert_not_nil run.completed_at
    assert_operator run.duration_ms, :>=, 1_500
  end

  test "finish! merges metadata rather than replacing it" do
    run = create_run(output_metadata: { "provider" => "openai", "model" => "gpt-4o" })

    run.finish!(output: "ok", metadata: { "model" => "gpt-4o-mini", "action" => "summarize" })

    assert_equal({ "provider" => "openai", "model" => "gpt-4o-mini", "action" => "summarize" },
                 run.reload.output_metadata)
  end

  test "finish! keeps usage already recorded mid-run" do
    run = create_run(status: :running, input_tokens: 90, output_tokens: 10, total_tokens: 105)

    run.finish!(output: "ok")
    run.reload

    assert_equal 90, run.input_tokens
    assert_equal 10, run.output_tokens
    assert_equal 105, run.total_tokens
  end

  test "finish! stores a provider-reported total that exceeds input plus output" do
    run = create_run(status: :running)

    run.finish!(output: "ok", input_tokens: 100, output_tokens: 20, total_tokens: 400)

    assert_equal 400, run.reload.total_tokens
  end

  test "finish! leaves duration nil when the run never started" do
    run = create_run

    run.finish!(output: "ok")

    assert_nil run.reload.duration_ms
  end

  test "fail! records the exception message and a bounded backtrace" do
    run = create_run(status: :running, started_at: 1.second.ago)
    error = ArgumentError.new("provider rejected the request")
    error.set_backtrace((1..25).map { |line| "frame #{line}" })

    run.fail!(error)
    run.reload

    assert run.failed?
    assert_equal "provider rejected the request", run.error_message
    assert_equal 10, run.error_backtrace.lines.size
    assert_equal "frame 1", run.error_backtrace.lines.first.chomp
    assert_not_nil run.completed_at
    assert_not_nil run.duration_ms
  end

  test "fail! accepts a plain message" do
    run = create_run(status: :running)

    run.fail!("timed out")

    assert_equal "timed out", run.reload.error_message
    assert_nil run.error_backtrace
  end

  test "fail! tolerates an exception with no backtrace" do
    run = create_run(status: :running)

    run.fail!(ArgumentError.new("never raised"))

    assert run.reload.failed?
    assert_nil run.error_backtrace
  end

  test "cancel! cancels an in-progress run and reports that it did" do
    run = create_run(status: :running, started_at: 1.second.ago)

    assert run.cancel!
    run.reload

    assert run.cancelled?
    assert_equal "Cancelled by user", run.error_message
    assert_not_nil run.completed_at
    assert_not_nil run.duration_ms
  end

  test "cancel! accepts a reason" do
    run = create_run(status: :pending)

    run.cancel!(reason: "Quota exhausted")

    assert_equal "Quota exhausted", run.reload.error_message
  end

  test "cancel! does not overwrite an error message already recorded" do
    run = create_run(status: :running, error_message: "provider degraded")

    run.cancel!

    assert_equal "provider degraded", run.reload.error_message
  end

  test "cancel! leaves a finished run untouched and reports that it did nothing" do
    run = create_run(status: :complete, output: "done")

    assert_not run.cancel!
    run.reload

    assert run.complete?
    assert_equal "done", run.output
    assert_nil run.error_message
  end

  test "the enum's bare setters move status without the lifecycle bookkeeping" do
    bare = create_run(status: :running, started_at: 1.second.ago)
    bare.complete!

    assert bare.complete?
    assert_nil bare.completed_at, "the enum setter is not a lifecycle transition"

    managed = create_run(status: :running, started_at: 1.second.ago)
    managed.finish!(output: "ok")

    assert_not_nil managed.completed_at
  end

  # --- duration -----------------------------------------------------------

  test "calculated_duration_ms prefers the stored value" do
    run = create_run(duration_ms: 42, started_at: 10.seconds.ago, completed_at: Time.current)

    assert_equal 42, run.calculated_duration_ms
  end

  test "calculated_duration_ms derives from the timestamps" do
    started = Time.current
    run = create_run(started_at: started, completed_at: started + 1.5)

    assert_equal 1_500, run.calculated_duration_ms
  end

  test "calculated_duration_ms accepts a fallback end for a run still finishing" do
    started = Time.current
    run = create_run(started_at: started)

    assert_nil run.calculated_duration_ms
    assert_equal 2_000, run.calculated_duration_ms(fallback_end: started + 2)
  end

  test "calculated_duration_ms is nil for a run that never started" do
    assert_nil create_run(completed_at: Time.current).calculated_duration_ms
  end

  # --- token totals -------------------------------------------------------

  test "total_tokens prefers the provider-reported column" do
    run = create_run(input_tokens: 10, output_tokens: 5, total_tokens: 90)

    assert_equal 90, run.total_tokens
  end

  test "total_tokens falls back to input plus output when no total was reported" do
    run = create_run(input_tokens: 10, output_tokens: 5)

    assert_equal 15, run.total_tokens
  end

  test "total_tokens is zero when nothing is known" do
    assert_equal 0, create_run.total_tokens
  end

  test "total_tokens_sum counts the fallback rows a bare SQL SUM misses" do
    create_run(input_tokens: 10, output_tokens: 5, total_tokens: 90)
    create_run(input_tokens: 10, output_tokens: 5)
    create_run(input_tokens: nil, output_tokens: nil)

    assert_equal 90, AgentRun.sum(:total_tokens), "the documented undercount"
    assert_equal 105, AgentRun.total_tokens_sum
  end

  test "total_tokens_sum narrows with the relation" do
    create_run(status: :complete, input_tokens: 10, output_tokens: 5)
    create_run(status: :failed, input_tokens: 100, output_tokens: 50)

    assert_equal 15, AgentRun.successful.total_tokens_sum
  end

  # --- progress events ----------------------------------------------------

  test "append_event writes a structured event and returns it" do
    run = create_run

    event = run.append_event(kind: :llm, label: "gpt-4o", eid: "e1", status: "started")

    assert_equal "e1", event["eid"]
    assert_equal "llm", event["kind"]
    assert_equal "gpt-4o", event["label"]
    assert_equal "started", event["status"]
    assert_equal [ event ], run.reload.events_log
  end

  test "append_event omits an absent eid rather than storing a nil" do
    run = create_run

    assert_not_includes run.append_event(kind: "tool", label: "search").keys, "eid"
  end

  test "append_event carries optional detail and duration" do
    run = create_run

    event = run.append_event(kind: "tool", label: "search", detail: "3 results", duration_ms: 12)

    assert_equal "3 results", event["detail"]
    assert_equal 12, event["duration_ms"]
  end

  test "append_event truncates runaway detail" do
    run = create_run

    event = run.append_event(kind: "tool", label: "search", detail: "x" * 5_000)

    assert_equal SolidAgent::Records::AgentRun::DETAIL_LIMIT, event["detail"].bytesize
  end

  test "append_event skips validations, callbacks and updated_at" do
    run = create_run
    run.update_column(:trace_id, nil)
    original_updated_at = run.reload.updated_at

    run.append_event(kind: "llm", label: "gpt-4o")

    assert_equal 1, run.reload.events_log.size
    assert_equal original_updated_at.to_i, run.updated_at.to_i
  end

  test "append_event re-reads the column so concurrent appends do not clobber" do
    run = create_run
    run.append_event(kind: "llm", label: "first")

    AgentRun.find(run.id).append_event(kind: "tool", label: "from another thread")
    run.append_event(kind: "llm", label: "third")

    assert_equal [ "first", "from another thread", "third" ], run.reload.events_log.map { |e| e["label"] }
  end

  test "add_log appends a log entry through a normal save" do
    run = create_run

    entry = run.add_log("Starting execution")

    assert_equal "info", entry["level"]
    assert_equal "Starting execution", entry["message"]
    assert_not_nil entry["timestamp"]
    assert_equal [ entry ], run.reload.events_log
  end

  test "add_log takes a level" do
    run = create_run

    assert_equal "error", run.add_log("Execution failed", level: :error)["level"]
  end

  test "add_log and append_event share one column and interleave safely" do
    run = create_run

    run.add_log("Starting execution")
    AgentRun.find(run.id).append_event(kind: "llm", label: "gpt-4o")
    run.add_log("Execution completed successfully")

    stream = run.reload.events_log

    assert_equal 3, stream.size
    assert_equal [ "message", "label", "message" ], stream.map { |entry| entry.key?("message") ? "message" : "label" }
  end

  test "events_log is empty rather than nil before anything is written" do
    assert_empty create_run.events_log
  end

  test "the events column name is configurable per model" do
    assert_equal :events, AgentRun.events_column
    assert_equal :logs, PlatformRun.events_column

    run = PlatformRun.create!(agent_id: @agent.id)
    run.append_event(kind: "llm", label: "gpt-4o")
    run.add_log("Starting execution")

    assert_equal 2, run.reload.logs.size
    assert_equal 2, run.events_log.size
  end

  test "a mismatched events column raises a directive error" do
    run = MisconfiguredRun.create!

    error = assert_raises(SolidAgent::Error) { run.append_event(kind: "llm", label: "gpt-4o") }

    assert_includes error.message, "has no logs column"
    assert_includes error.message, "MisconfiguredRun.events_column"
  end

  # --- instructions fingerprinting ---------------------------------------

  test "record_instructions stores the digest without saving" do
    run = create_run

    digest = run.record_instructions("You are a helpful agent.")

    assert_equal SolidAgent::RunFingerprint.digest("You are a helpful agent."), digest
    assert_equal digest, run.instructions_digest
    assert_nil AgentRun.where(id: run.id).pick(:instructions_digest)
  end

  test "instructions_digest falls back to the instructions in output_metadata" do
    run = create_run(output_metadata: { "instructions" => "You are a helpful agent." })

    assert_equal SolidAgent::RunFingerprint.digest("You are a helpful agent."), run.instructions_digest
  end

  test "the stored digest wins over the metadata fallback" do
    run = create_run(instructions_digest: "deadbeef", output_metadata: { "instructions" => "other" })

    assert_equal "deadbeef", run.instructions_digest
  end

  test "instructions_digest is nil when nothing recorded any instructions" do
    assert_nil create_run.instructions_digest
    assert_nil create_run.instructions_codename
  end

  test "instructions_codename is a deterministic name for the digest" do
    run = create_run(output_metadata: { "instructions" => "You are a helpful agent." })

    assert_equal SolidAgent::RunFingerprint.codename(run.instructions_digest), run.instructions_codename
    assert_match(/\A[a-z]+-[a-z]+\z/, run.instructions_codename)
  end

  # --- subject ------------------------------------------------------------

  test "subject is the polymorphic runnable when one is attached" do
    workflow = Workflow.create!(name: "Nightly digest")
    run = create_run(runnable: workflow)

    assert_equal workflow, run.subject
  end

  test "subject falls back to the agent record" do
    assert_equal @agent, create_run.subject
  end

  test "the runnable wins over the agent when both are set" do
    workflow = Workflow.create!(name: "Nightly digest")
    run = create_run(runnable: workflow)

    assert_equal @agent, run.agent
    assert_equal workflow, run.subject
  end

  test "subject is nil for a run about nothing persisted" do
    assert_nil AgentRun.create!(input_prompt: "ad hoc").subject
  end

  # --- summary ------------------------------------------------------------

  test "summary reports the display fields" do
    run = create_run(
      status: :complete,
      action_name: "summarize",
      input_prompt: "a" * 200,
      output: "b" * 400,
      duration_ms: 1_234,
      input_tokens: 10,
      output_tokens: 5,
      error_message: nil,
      output_metadata: { "provider" => "openai", "model" => "gpt-4o", "instructions" => "c" * 300 }
    )

    summary = run.summary

    assert_equal run.id, summary[:id]
    assert_equal "complete", summary[:status]
    assert_equal 100, summary[:input_preview].length
    assert_equal 200, summary[:output_preview].length
    assert_equal 1_234, summary[:duration_ms]
    assert_equal 15, summary[:tokens]
    assert_equal "openai", summary[:provider]
    assert_equal "gpt-4o", summary[:model]
    assert_equal "summarize", summary[:action_name]
    assert_equal 120, summary[:instructions_preview].length
    assert_equal run.instructions_digest, summary[:instructions_digest]
    assert_equal run.instructions_codename, summary[:instructions_codename]
    assert_equal run.created_at, summary[:created_at]
    assert_nil summary[:error]
  end

  test "summary falls back through action_name to the metadata to a default" do
    assert_equal "ask", create_run.summary[:action_name]
    assert_equal "summarize", create_run(output_metadata: { "action" => "summarize" }).summary[:action_name]
    assert_equal "translate", create_run(action_name: "translate",
                                         output_metadata: { "action" => "summarize" }).summary[:action_name]
  end

  test "summary carries the error message of a failed run" do
    run = create_run(status: :running)
    run.fail!("timed out")

    assert_equal "timed out", run.summary[:error]
  end

  # --- trace ids ----------------------------------------------------------

  test "a trace id is assigned on create" do
    assert_match(/\A[0-9a-f-]{36}\z/, create_run.trace_id)
  end

  test "an explicit trace id is kept" do
    assert_equal "trace-123", create_run(trace_id: "trace-123").trace_id
  end

  test "a nil trace id on an existing row is healed rather than rejected" do
    run = create_run
    run.update_column(:trace_id, nil)

    assert run.reload.save
    assert_not_nil run.trace_id
  end

  test "a blank trace id is rejected" do
    run = create_run
    run.trace_id = ""

    assert_not run.valid?
    assert_includes run.errors[:trace_id], "can't be blank"
  end

  # --- notifications ------------------------------------------------------

  test "a committed status change instruments the status event" do
    run = create_run(status: :running)
    events = capture_status_events { run.finish!(output: "ok") }

    assert_equal 1, events.size
    payload = events.first
    assert_equal run, payload[:run]
    assert_equal "running", payload[:from]
    assert_equal "complete", payload[:to]
    assert_equal run.trace_id, payload[:trace_id]
  end

  test "changes that leave the status alone instrument nothing" do
    run = create_run(status: :running)

    assert_empty capture_status_events { run.update!(output: "partial") }
  end

  test "creating a run instruments nothing" do
    assert_empty capture_status_events { create_run(status: :running) }
  end

  test "cancelling instruments the status event" do
    run = create_run(status: :running)

    events = capture_status_events { run.cancel! }

    assert_equal "cancelled", events.first[:to]
  end

  # --- scopes -------------------------------------------------------------

  test "recent orders newest first" do
    old = create_run(created_at: 2.days.ago)
    new = create_run(created_at: 1.hour.ago)

    assert_equal [ new, old ], AgentRun.recent.to_a
  end

  test "successful and failed_runs select terminal states" do
    done = create_run(status: :complete)
    broken = create_run(status: :failed)
    create_run(status: :running)

    assert_equal [ done ], AgentRun.successful.to_a
    assert_equal [ broken ], AgentRun.failed_runs.to_a
  end

  test "today excludes yesterday" do
    today = create_run
    create_run(created_at: 2.days.ago)

    assert_equal [ today ], AgentRun.today.to_a
  end

  test "correlation scopes select by name, action, trace and status" do
    run = create_run(agent_name: "SupportAgent", action_name: "summarize",
                     trace_id: "trace-1", status: :running)
    create_run(agent_name: "SalesAgent", action_name: "draft", trace_id: "trace-2", status: :complete)

    assert_equal [ run ], AgentRun.for_agent("SupportAgent").to_a
    assert_equal [ run ], AgentRun.for_action("summarize").to_a
    assert_equal [ run ], AgentRun.with_trace("trace-1").to_a
    assert_equal [ run ], AgentRun.for_status(:running).to_a
  end

  # --- the configurable seam ---------------------------------------------

  test "the agent association is named from SolidAgent.agent_class as a string" do
    assert_equal "Assistant", AssistantRun.reflect_on_association(:agent).options[:class_name]
    assert_equal "Agent", AgentRun.reflect_on_association(:agent).options[:class_name]
  end

  test "a differently named agent model loads through the association" do
    assistant = Assistant.create!(name: "Ops", slug: "ops")
    run = AssistantRun.create!(agent_id: assistant.id)

    assert_instance_of Assistant, run.reload.agent
  end

  test "both owners are optional" do
    assert AgentRun.new.valid?
  end

  # --- schema compatibility ----------------------------------------------

  test "the platform schema runs a full lifecycle without runnable or instructions_digest" do
    run = PlatformRun.create!(agent_id: @agent.id, input_prompt: "summarize this", action_name: "summarize")
    run.start!
    run.add_log("Starting execution")
    run.finish!(output: "done", metadata: { "provider" => "openai", "instructions" => "Be brief." },
                input_tokens: 10, output_tokens: 5, total_tokens: 15)
    run.reload

    assert run.complete?
    assert_equal 15, run.total_tokens
    assert_equal @agent, run.subject
    assert_nil run.record_instructions("Be brief.")
    assert_equal SolidAgent::RunFingerprint.digest("Be brief."), run.instructions_digest
    assert_equal "summarize", run.summary[:action_name]
  end

  test "the platform schema records a backtrace" do
    run = PlatformRun.create!(agent_id: @agent.id, status: :running)
    error = ArgumentError.new("boom")
    error.set_backtrace([ "frame 1" ])

    run.fail!(error)

    assert_equal "frame 1", run.reload.error_backtrace
  end

  test "the legacy schema runs a full lifecycle without total_tokens or a backtrace" do
    workflow = Workflow.create!(name: "Nightly digest")
    run = LegacyRun.create!(runnable: workflow, agent_name: "DigestAgent")
    run.start!
    run.append_event(kind: "llm", label: "gpt-4o")
    run.record_instructions("Be brief.")
    run.finish!(output: "done", input_tokens: 10, output_tokens: 5, total_tokens: 400)
    run.reload

    assert run.complete?
    assert_equal workflow, run.subject
    assert_equal 15, run.total_tokens, "a total the table cannot store falls back to the sum"
    assert_equal SolidAgent::RunFingerprint.digest("Be brief."), run.instructions_digest
    assert_equal 1, run.events_log.size
  end

  test "the legacy schema drops a backtrace it has nowhere to put" do
    run = LegacyRun.create!(agent_name: "DigestAgent", status: :running)
    error = ArgumentError.new("boom")
    error.set_backtrace([ "frame 1" ])

    run.fail!(error)

    assert run.reload.failed?
    assert_equal "boom", run.error_message
  end

  test "total_tokens_sum works on a table with no total_tokens column" do
    LegacyRun.create!(agent_name: "DigestAgent", input_tokens: 10, output_tokens: 5)
    LegacyRun.create!(agent_name: "DigestAgent", input_tokens: 1, output_tokens: nil)

    assert_equal 16, LegacyRun.total_tokens_sum
  end

  private

  def create_run(attributes = {})
    AgentRun.create!({ agent: @agent }.merge(attributes))
  end

  def capture_status_events
    captured = []
    subscriber = ActiveSupport::Notifications.subscribe(
      SolidAgent::Records::AgentRun::STATUS_CHANGED_EVENT
    ) { |*, payload| captured << payload }
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

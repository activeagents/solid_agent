# frozen_string_literal: true

# A single agent execution: lifecycle status, inputs/outputs, usage, and
# an append-only stream of progress events. Correlates with AgentContext/
# AgentGeneration rows and telemetry traces via trace_id.
class AgentRun < ApplicationRecord
  belongs_to :runnable, polymorphic: true, optional: true

  STATUSES = %w[pending running complete failed cancelled].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
  scope :for_action, ->(action_name) { where(action_name: action_name) }
  scope :with_trace, ->(trace_id) { where(trace_id: trace_id) }
  scope :for_status, ->(status) { where(status: status) }

  STATUSES.each do |status_name|
    define_method("#{status_name}?") { status == status_name }
  end

  def in_progress?
    pending? || running?
  end

  def finished?
    complete? || failed? || cancelled?
  end

  # === Lifecycle ===

  def start!
    update!(status: "running", started_at: Time.current)
  end

  def complete!(output: nil, metadata: {}, input_tokens: nil, output_tokens: nil)
    update!(
      status: "complete",
      output: output,
      output_metadata: (output_metadata || {}).merge(metadata),
      input_tokens: input_tokens || self.input_tokens,
      output_tokens: output_tokens || self.output_tokens,
      completed_at: Time.current,
      duration_ms: calculated_duration_ms(fallback_end: Time.current)
    )
  end

  def fail!(error)
    update!(
      status: "failed",
      error_message: error.respond_to?(:message) ? error.message : error.to_s,
      completed_at: Time.current,
      duration_ms: calculated_duration_ms(fallback_end: Time.current)
    )
  end

  def cancel!
    return false if finished?

    update!(status: "cancelled", completed_at: Time.current)
    true
  end

  # === Progress events ===

  # Appends a progress event mid-run so pollers can stream what the agent
  # is doing (pending llm/tool/agent calls). Events pair up by eid: a
  # "started" event is pending until a "done"/"error" with the same eid
  # lands. update_column: no validations/callbacks, so this is safe to call
  # from the run's own execution thread.
  #
  # Read-modify-write on a JSON column drops entries when two writers race,
  # so the re-read and the write are serialized by a row lock.
  def append_event(kind:, label:, eid: nil, status: "done", detail: nil, duration_ms: nil)
    event = {
      "at" => Time.current.iso8601(3),
      "eid" => eid,
      "kind" => kind.to_s,
      "label" => label.to_s,
      "status" => status.to_s
    }.compact
    event["detail"] = detail.to_s.byteslice(0, 1200).to_s.scrub if detail
    event["duration_ms"] = duration_ms if duration_ms

    with_lock do
      current = self.class.where(id: id).pick(:events) || []
      update_column(:events, current + [ event ])
    end

    event
  end

  # === Cohort fingerprinting ===

  # Records the instructions this run executed under as a stable digest —
  # the grouping key (with model) for configuration cohorts.
  def record_instructions(instructions)
    self.instructions_digest = SolidAgent::RunFingerprint.digest(instructions)
  end

  # Deterministic memorable name for the digest ("calm-heron") — reads far
  # better than hex when comparing cohorts.
  def instructions_codename
    SolidAgent::RunFingerprint.codename(instructions_digest)
  end

  # === Usage ===

  def total_tokens
    input_tokens.to_i + output_tokens.to_i
  end

  def calculated_duration_ms(fallback_end: nil)
    return duration_ms if duration_ms.present?

    finish = completed_at || fallback_end
    return nil unless started_at && finish

    ((finish - started_at) * 1000).to_i
  end
end

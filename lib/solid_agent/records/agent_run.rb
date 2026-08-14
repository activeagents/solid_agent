# frozen_string_literal: true

require_relative "../run_fingerprint"

module SolidAgent
  module Records
    # Behavior for the +AgentRun+ record: one execution of an agent, from
    # enqueue through terminal state, with its inputs, outputs, token usage and
    # an append-only stream of progress events.
    #
    # == Two schemas, one concern
    #
    # This record exists in the wild in two shapes, and the concern has to fit
    # both without asking anyone to migrate a live table:
    #
    # * The platform shape — +agent_id+, an *integer* +status+ enum, +logs+,
    #   +total_tokens+, +error_backtrace+.
    # * The gem's earlier generator shape — a polymorphic +runnable+, a *string*
    #   +status+, +events+, +instructions_digest+, and neither +total_tokens+
    #   nor +error_backtrace+.
    #
    # The integer enum and +agent_id+ win: they are what is deployed and
    # queried in production. The polymorphic +runnable+ and +instructions_digest+
    # are kept as additions, so a run can be about a persisted agent record *or*
    # about an arbitrary host object (a workflow, a job, a document). {#subject}
    # is the one reader that does not care which.
    #
    # The log column is the only irreconcilable name, so it is not reconciled —
    # {events_column} names it, defaulting to +:events+. A host on the platform
    # schema sets it to +:logs+ and keeps its table.
    #
    # Every column only one shape has — +total_tokens+, +error_backtrace+,
    # +instructions_digest+, +agent_id+, +runnable_type+ — is guarded, so
    # including this concern on either table works and writes simply skip what
    # is not there.
    #
    # == What is deliberately absent
    #
    # The platform broadcasts status changes over ActionCable. That couples a
    # persistence concern to a delivery mechanism the host may not run, so this
    # emits {STATUS_CHANGED_EVENT} instead and lets a dashboard subscribe and
    # broadcast however it likes.
    #
    # @example Configure a host that kept the platform's +logs+ column
    #   class AgentRun < ApplicationRecord
    #     include SolidAgent::Records::AgentRun
    #     self.events_column = :logs
    #   end
    #
    # @example Drive a run through its lifecycle
    #   run = AgentRun.create!(agent: agent, input_prompt: "summarize this")
    #   run.start!
    #   run.append_event(kind: "llm", label: "gpt-4o", eid: "1", status: "started")
    #   run.finish!(output: "…", input_tokens: 120, output_tokens: 40)
    #   run.total_tokens #=> 160
    #
    # @example Re-broadcast status changes from the host
    #   ActiveSupport::Notifications.subscribe("run.status_changed.solid_agent") do |*, payload|
    #     ActionCable.server.broadcast("agent_run_#{payload[:run].id}", payload[:run].summary)
    #   end
    module AgentRun
      extend ActiveSupport::Concern

      # Integer-backed lifecycle. The values are the ones already persisted in
      # production rows and must not be renumbered.
      STATUSES = { pending: 0, running: 1, complete: 2, failed: 3, cancelled: 4 }.freeze

      # Emitted after a committed status change. Payload: +:run+, +:from+,
      # +:to+, +:trace_id+.
      STATUS_CHANGED_EVENT = "run.status_changed.solid_agent"

      # Event +detail+ is operator-facing context, not a payload to preserve —
      # a runaway tool response must not turn the events column into the
      # largest row in the table.
      DETAIL_LIMIT = 1200

      # Enough backtrace to name the failing frame and its callers; the full
      # trace belongs in the exception reporter, not in every run row.
      BACKTRACE_LINES = 10

      INPUT_PREVIEW_LIMIT = 100
      OUTPUT_PREVIEW_LIMIT = 200
      INSTRUCTIONS_PREVIEW_LIMIT = 120

      # What {#summary} reports when neither the column nor the metadata names
      # an action — every agent has a default entry point, and callers group by
      # this field.
      DEFAULT_ACTION_NAME = "ask"

      included do
        # Named with the configured class *string* so a host can point the
        # records layer at +Ai::Assistant+ without the gem ever constantizing
        # an autoloadable constant at load time.
        #
        # optional: true, unlike the platform's required +belongs_to :agent+ —
        # a run may be about a +runnable+ instead, or about nothing persisted
        # at all when a bare executor just wants the audit row. Hosts that want
        # the stricter rule add `validates :agent, presence: true`.
        belongs_to :agent, class_name: SolidAgent.agent_class.to_s, optional: true
        belongs_to :runnable, polymorphic: true, optional: true

        # The log column's name, not its contents. Making it configurable is
        # what lets the platform keep +logs+ and the generator keep +events+
        # without either side renaming a column on a live table.
        class_attribute :events_column, default: :events

        # No prefix or suffix: `run.complete?`, `run.failed?` and
        # `run.cancelled?` are called by name across the platform's jobs and
        # controllers, and prefixing would rename all of them.
        #
        # The cost is that the enum also generates bare `complete!`, `failed!`
        # and `cancelled!` setters into a module that sits *above* this concern
        # in the ancestor chain. They silently win over any same-named method
        # defined here — with no warning from Rails — which is why the
        # lifecycle transitions below are named {#finish!} and {#fail!}. Those
        # bare setters remain callable and move `status` without touching
        # `completed_at` or `duration_ms`; prefer the lifecycle methods.
        enum :status, STATUSES

        validates :trace_id, presence: true

        scope :recent, -> { order(created_at: :desc) }
        scope :successful, -> { where(status: :complete) }
        # `failed` is already taken by the enum's own scope, which is why this
        # one carries the suffix.
        scope :failed_runs, -> { where(status: :failed) }
        scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
        scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
        scope :for_action, ->(action_name) { where(action_name: action_name) }
        scope :with_trace, ->(trace_id) { where(trace_id: trace_id) }
        scope :for_status, ->(status) { where(status: status) }

        # Not `on: :create`: rows written before trace_id was mandatory would
        # otherwise be unsavable forever, failing a presence validation on a
        # column nothing is filling in. Healing them on the next write is
        # cheaper than a backfill migration.
        before_validation :assign_trace_id

        after_update_commit :notify_status_change, if: :saved_change_to_status?
      end

      class_methods do
        # Sums token usage across the relation, falling back per row to
        # input + output where the provider reported no total.
        #
        # This exists because +sum(:total_tokens)+ silently undercounts: the
        # fallback in {#total_tokens} lives in Ruby, so a row whose provider
        # reported only input and output counts as zero in SQL. That is a known
        # wart of keeping a denormalized total column at all, not a bug to
        # paper over — the column is authoritative when present because some
        # providers bill for tokens neither prompt nor completion accounts for
        # (cached reads, reasoning), so it cannot simply be dropped.
        #
        # @return [Integer]
        #
        # @example
        #   AgentRun.today.total_tokens_sum   #=> 41_233
        #   AgentRun.today.sum(:total_tokens) #=> 12_004, missing every fallback row
        def total_tokens_sum
          fallback = "COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)"
          expression =
            if column_names.include?("total_tokens")
              "COALESCE(total_tokens, #{fallback})"
            else
              fallback
            end

          all.sum(Arel.sql(expression)).to_i
        end
      end

      # The thing this run was about: the polymorphic +runnable+ when the host
      # attached one, otherwise the agent record.
      #
      # @return [ActiveRecord::Base, nil]
      def subject
        association_if_present(:runnable, :runnable_id) || association_if_present(:agent, :agent_id)
      end

      # @return [Boolean] whether the run has not reached a terminal state
      def in_progress?
        pending? || running?
      end

      # @return [Boolean] whether the run reached any terminal state, successful or not
      def finished?
        complete? || failed? || cancelled?
      end

      # === Lifecycle ===

      # Marks the run as running and stamps +started_at+.
      #
      # @return [Boolean]
      def start!
        update!(persistable(status: :running, started_at: Time.current))
      end

      # Completes the run: output, merged metadata, usage and duration.
      #
      # Named +finish!+ rather than +complete!+ because the enum owns that
      # name — see the note on {STATUSES} in the +included+ block.
      #
      # Usage arguments are nil-tolerant and fall back to whatever is already
      # on the record, so an executor that recorded tokens incrementally
      # mid-run does not have to repeat them here.
      #
      # @param output [String, nil]
      # @param metadata [Hash] merged into +output_metadata+, not replacing it
      # @param input_tokens [Integer, nil]
      # @param output_tokens [Integer, nil]
      # @param total_tokens [Integer, nil] the provider's own total, when it reported one
      # @return [Boolean]
      def finish!(output: nil, metadata: {}, input_tokens: nil, output_tokens: nil, total_tokens: nil)
        finished_at = Time.current

        update!(persistable(
          status: :complete,
          output: output,
          output_metadata: (output_metadata || {}).merge(metadata || {}),
          input_tokens: input_tokens || self.input_tokens,
          output_tokens: output_tokens || self.output_tokens,
          total_tokens: total_tokens || self[:total_tokens],
          completed_at: finished_at,
          duration_ms: calculated_duration_ms(fallback_end: finished_at)
        ))
      end

      # Records a failure. Accepts an exception or a plain message.
      #
      # @param error [Exception, String]
      # @return [Boolean]
      def fail!(error)
        finished_at = Time.current

        update!(persistable(
          status: :failed,
          error_message: error.respond_to?(:message) ? error.message : error.to_s,
          error_backtrace: backtrace_for(error),
          completed_at: finished_at,
          duration_ms: calculated_duration_ms(fallback_end: finished_at)
        ))
      end

      # Cancels a run that has not finished.
      #
      # A finished run is left exactly as it was — cancelling a run that
      # already succeeded would rewrite history — and the caller is told so by
      # the return value rather than by an exception, because "the run beat me
      # to it" is a race, not a fault.
      #
      # @param reason [String] recorded as +error_message+ when none is set
      # @return [Boolean] whether this call performed the cancellation
      def cancel!(reason: "Cancelled by user")
        return false unless in_progress?

        finished_at = Time.current

        update!(persistable(
          status: :cancelled,
          completed_at: finished_at,
          duration_ms: calculated_duration_ms(fallback_end: finished_at),
          error_message: error_message.presence || reason
        ))
        true
      end

      # === Progress events ===

      # @return [Array<Hash>] the event stream, oldest first
      def events_log
        self[events_attribute] || []
      end

      # Appends a progress event so pollers can stream what the agent is doing.
      #
      # Events pair up by +eid+: a "started" event is pending until a "done" or
      # "error" event with the same +eid+ lands, which is how a UI shows an
      # in-flight LLM or tool call.
      #
      # Writes with +update_column+ — no validations, no callbacks, no
      # +updated_at+ churn — so it is safe to call from the run's own execution
      # thread mid-transaction, and it re-reads the column from the database
      # first so interleaved appends do not clobber each other.
      #
      # @param kind [String, Symbol] "llm", "tool", "agent", …
      # @param label [String, Symbol] human-readable name of the thing happening
      # @param eid [String, nil] correlation id pairing a start with its end
      # @param status [String] "started", "done" or "error"
      # @param detail [String, nil] truncated to {DETAIL_LIMIT} bytes
      # @param duration_ms [Integer, nil]
      # @return [Hash] the event as written
      def append_event(kind:, label:, eid: nil, status: "done", detail: nil, duration_ms: nil)
        event = {
          "at" => Time.current.iso8601(3),
          "eid" => eid,
          "kind" => kind.to_s,
          "label" => label.to_s,
          "status" => status.to_s
        }.compact
        event["detail"] = truncated_detail(detail) if detail
        event["duration_ms"] = duration_ms if duration_ms

        update_column(events_attribute, current_events + [ event ])
        event
      end

      # Appends a human-readable log line to the same stream.
      #
      # Log entries carry +timestamp+/+level+/+message+ while events carry
      # +at+/+kind+/+label+; both shapes are already persisted and both are
      # read by existing dashboards, so they coexist in one column rather than
      # one being rewritten into the other.
      #
      # Unlike {#append_event} this saves normally, so validations and
      # callbacks run — a log line is usually written from the caller's own
      # thread, where a full save is what is wanted.
      #
      # @param message [String]
      # @param level [String, Symbol]
      # @return [Hash] the entry as written
      def add_log(message, level: :info)
        entry = {
          "timestamp" => Time.current.iso8601,
          "level" => level.to_s,
          "message" => message.to_s
        }

        update!(events_attribute => current_events + [ entry ])
        entry
      end

      # === Cohort fingerprinting ===

      # Records the instructions this run executed under as a stable digest —
      # the grouping key (with model) for configuration cohorts.
      #
      # A no-op on a schema without the column, where the digest is derived
      # from +output_metadata+ instead. Assigns without saving, so an executor
      # can set it alongside everything else it is about to persist.
      #
      # @param instructions [String, nil]
      # @return [String, nil] the digest assigned
      def record_instructions(instructions)
        return nil unless self.class.column_names.include?("instructions_digest")

        self[:instructions_digest] = SolidAgent::RunFingerprint.digest(instructions)
      end

      # Stable 8-character fingerprint of the instructions this run executed
      # under.
      #
      # Prefers the stored column and falls back to hashing
      # +output_metadata["instructions"]+, because the platform never had the
      # column and computed this on read. Both paths use the same digest
      # function, so cohorts computed either way group together.
      #
      # @return [String, nil]
      def instructions_digest
        stored = self[:instructions_digest] if self.class.column_names.include?("instructions_digest")

        stored.presence || SolidAgent::RunFingerprint.digest(metadata_value("instructions"))
      end

      # @return [String, nil] deterministic "calm-heron" name for the digest
      def instructions_codename
        SolidAgent::RunFingerprint.codename(instructions_digest)
      end

      # === Usage and timing ===

      # Total tokens the run consumed.
      #
      # The stored column wins when the provider reported one — it can exceed
      # input + output, since cached and reasoning tokens are billed but not
      # counted in either. Otherwise the two are summed, which is why a bare
      # +SUM(total_tokens)+ in SQL undercounts; use {.total_tokens_sum}.
      #
      # @return [Integer]
      def total_tokens
        reported = self[:total_tokens] if self.class.column_names.include?("total_tokens")
        return reported unless reported.nil?

        input_tokens.to_i + output_tokens.to_i
      end

      # Duration in milliseconds: the stored value when set, otherwise derived
      # from the timestamps.
      #
      # @param fallback_end [Time, nil] stands in for +completed_at+ while the
      #   run is being finished and the column is not written yet
      # @return [Integer, nil] nil when the run never started
      def calculated_duration_ms(fallback_end: nil)
        return duration_ms if duration_ms.present?

        finish = completed_at || fallback_end
        return nil unless started_at && finish

        ((finish - started_at) * 1000).to_i
      end

      # A display-sized digest of the run, as consumed by run lists and APIs.
      #
      # @return [Hash]
      def summary
        {
          id: id,
          status: status,
          input_preview: input_prompt&.truncate(INPUT_PREVIEW_LIMIT),
          output_preview: output&.truncate(OUTPUT_PREVIEW_LIMIT),
          duration_ms: calculated_duration_ms,
          tokens: total_tokens,
          provider: metadata_value("provider"),
          model: metadata_value("model"),
          action_name: action_name || metadata_value("action") || DEFAULT_ACTION_NAME,
          instructions_digest: instructions_digest,
          instructions_codename: instructions_codename,
          instructions_preview: metadata_value("instructions")&.truncate(INSTRUCTIONS_PREVIEW_LIMIT),
          created_at: created_at,
          error: error_message
        }
      end

      private

      def assign_trace_id
        self.trace_id ||= SecureRandom.uuid
      end

      def notify_status_change
        from, to = saved_change_to_status

        ActiveSupport::Notifications.instrument(
          STATUS_CHANGED_EVENT,
          run: self, from: from, to: to, trace_id: trace_id
        )
      end

      # Drops attributes the host's table does not have, so one lifecycle
      # method serves both schemas instead of each transition growing a
      # column check.
      def persistable(attributes)
        columns = self.class.column_names
        attributes.select { |name, _| columns.include?(name.to_s) }
      end

      # nil rather than a raise when the foreign key is missing: each original
      # schema lacks the other's, and asking for the association the table does
      # not model is a legitimate question with the answer "none".
      def association_if_present(name, foreign_key)
        return nil unless self.class.column_names.include?(foreign_key.to_s)

        public_send(name)
      end

      def metadata_value(key)
        return nil unless self.class.column_names.include?("output_metadata")

        output_metadata&.dig(key)
      end

      # The configured log column, checked. A host that renamed the column but
      # not the setting would otherwise get a confusing nil from a json column
      # that does not exist.
      def events_attribute
        return events_column if self.class.column_names.include?(events_column.to_s)

        raise SolidAgent::Error,
              "#{self.class.name} has no #{events_column} column. Set " \
              "#{self.class.name}.events_column to the column holding run events."
      end

      # Reads through the database so concurrent appends from the executor and
      # the caller interleave instead of overwriting one another. An unsaved
      # record has nothing to re-read, so it keeps what is in memory.
      def current_events
        return events_log unless persisted?

        self.class.where(id: id).pick(events_attribute) || []
      end

      def truncated_detail(detail)
        detail.to_s.byteslice(0, DETAIL_LIMIT).to_s.scrub
      end

      def backtrace_for(error)
        return nil unless error.respond_to?(:backtrace)

        error.backtrace&.first(BACKTRACE_LINES)&.join("\n")
      end
    end
  end
end

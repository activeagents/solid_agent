# frozen_string_literal: true

require "securerandom"

require_relative "ownable"
require_relative "../run_fingerprint"

module SolidAgent
  module Records
    # Behavior for the +Agent+ record: a persisted agent configuration —
    # provider, model, instructions, action prompts, tools — that versions
    # itself as it is edited and can be executed.
    #
    # This is the largest of the record concerns, and the one hosts extend most,
    # which is why the model class stays in +app/models+ and only the behavior
    # ships here. Everything the concern reaches for outside its own row goes
    # through {SolidAgent} seams resolved at call time: the version model, the
    # run model, the execution job, the run executor. The gem never names
    # +Agent+, +AgentVersion+ or +AgentRun+ as constants.
    #
    # What deliberately did NOT come across from the platform model:
    #
    # * *Code generation.* +to_agent_class_code+ emits Ruby source for an
    #   ActiveAgent class. That is compilation, not persistence, and it belongs
    #   with the thing that knows the current agent DSL.
    # * *Closed vocabularies.* PRESET_TYPES, INSTRUCTION_SETS, AVAILABLE_TOOLS
    #   and PROVIDERS enumerate what one React component can render. They are
    #   product copy on a release cadence the gem does not control — PROVIDERS
    #   has already drifted between the two copies of this model — so hosts
    #   own them.
    #
    # The columns those vocabularies describe (+preset_type+, +appearance+) do
    # stay, because production +agent_versions+ rows already carry them inside
    # +configuration_snapshot+; dropping the columns would make every existing
    # version row lossy on restore.
    #
    # @example Editing an agent writes a version
    #   agent = Agent.create!(name: "Reviewer", provider: "openai", model: "gpt-4o")
    #   agent.version_count           #=> 1
    #   agent.update!(instructions: "Be terse.")
    #   agent.latest_version.change_summary #=> "Updated: instructions"
    #
    # @example Rolling back
    #   agent.restore_from_version!(agent.agent_versions.find_by(version_number: 1))
    module Agent
      extend ActiveSupport::Concern
      include Ownable

      # The action every agent has without declaring one: it runs under the
      # agent's base instructions alone.
      DEFAULT_ACTION = "ask"

      # The attributes whose change is worth a new version — the agent's
      # behavior, not its identity. Renaming an agent or moving it to another
      # provider is a fact about the record, not a revision to roll back to.
      #
      # In the platform model this list is written out twice, once to decide
      # whether to version and once to summarize what changed; the two are the
      # same list by definition and drift the moment a column is added.
      VERSIONED_FIELDS = %w[
        instructions action_prompts preset_type appearance instruction_sets
        tools mcp_servers model_config response_format
      ].freeze

      # Identity attributes recorded in a snapshot but never restored from one.
      # They give a version enough context to be read on its own ("this is what
      # the agent was called then") without letting a rollback rename the
      # record out from under its owner.
      DESCRIPTIVE_FIELDS = %w[name description provider model].freeze

      # Everything {#configuration_snapshot} captures.
      SNAPSHOT_FIELDS = (DESCRIPTIVE_FIELDS + VERSIONED_FIELDS).freeze

      included do
        # Both associations pin foreign_key: the host names this model, and
        # Rails would otherwise derive `platform_agent_id` from a class called
        # PlatformAgent while the child concerns declare `belongs_to :agent`
        # against a real `agent_id` column.
        has_many :agent_versions,
                 class_name: SolidAgent.agent_version_class.to_s,
                 foreign_key: :agent_id,
                 dependent: :destroy
        has_many :agent_runs,
                 class_name: SolidAgent.agent_run_class.to_s,
                 foreign_key: :agent_id,
                 dependent: :destroy

        validates :name, presence: true, length: { minimum: 2, maximum: 100 }
        validates :slug, presence: true, format: { with: /\A[a-z0-9\-_]+\z/ }
        validates :provider, presence: true
        validates :model, presence: true
        # Slug uniqueness is hand-rolled rather than declared, because the
        # scope is the ownership column and Ownable lets the host choose it.
        # A `uniqueness: { scope: :user_id }` option would freeze that choice
        # at include time.
        validate :slug_must_be_unique_for_owner
        validate :action_prompts_must_be_well_formed

        # `observed` agents were discovered from reported telemetry rather than
        # authored here. The platform cannot execute them — you cannot push
        # instructions into someone else's app — so they are read-only records
        # of something running elsewhere until a fork copies them.
        enum :status, { draft: 0, active: 1, archived: 2, observed: 3 }

        before_validation :generate_slug, on: :create
        after_create :create_initial_version, if: :versioned?
        after_update :create_version_on_config_change, if: :configuration_changed?

        scope :active_agents, -> { where(status: :active) }
        scope :observed_agents, -> { where(status: :observed) }
        scope :authored, -> { where.not(status: :observed) }
        scope :by_provider, ->(provider) { where(provider: provider) }

        # Finds agents whose tools array contains +tool+.
        #
        # This is the one query in the records layer that is not portable, and
        # it is asymmetric on purpose:
        #
        # * On Postgres it uses jsonb containment (`@>`), which is indexable
        #   with a GIN index and is what production runs. The column must be
        #   `jsonb` — `json` has no containment operator and raises.
        # * Everywhere else it falls back to a quoted LIKE against the
        #   serialized array. That matches `["search"]` without matching
        #   `["research"]`, but it is a substring test on text: it cannot use
        #   an index, and it would also match a tool name appearing as a key
        #   if a host stored objects rather than strings in `tools`. The
        #   explicit ESCAPE clause is not decoration — sqlite has no default
        #   escape character, so without it a tool named `c_de` would match
        #   `code`.
        #
        # The fallback exists so sqlite and MySQL hosts get an answer instead
        # of a StatementInvalid; Postgres remains the target.
        scope :with_tool, ->(tool) {
          if klass.jsonb_containment?
            where("tools @> ?", [ tool.to_s ].to_json)
          else
            where("tools LIKE ? ESCAPE '\\'", "%\"#{klass.sanitize_sql_like(tool.to_s)}\"%")
          end
        }
      end

      class_methods do
        # Whether this model's connection supports the jsonb containment
        # operator.
        #
        # Read from the configured adapter rather than by leasing a connection:
        # {with_tool} asks on every call, and building a relation should not
        # check out a connection to do it.
        #
        # @return [Boolean]
        def jsonb_containment?
          connection_db_config.adapter.to_s.match?(/postgres|postgis/i)
        end
      end

      # The ActiveAgent class name this agent's runs are recorded under — the
      # correlation key between an agent row, telemetry traces and solid_agent
      # contexts, all of which key on a class name string rather than an id.
      #
      # @return [String]
      def telemetry_agent_class
        configured = self[:agent_class_name] if has_attribute?(:agent_class_name)
        base = configured.presence || name.to_s.parameterize(separator: "_").camelize
        base.end_with?("Agent") ? base : "#{base}Agent"
      end

      # Every invokable action: the built-in default plus each named prompt.
      #
      # @return [Array<String>]
      def available_actions
        [ DEFAULT_ACTION ] + action_prompt_list.filter_map { |prompt| prompt["name"].presence }
      end

      # @param action_name [String, Symbol]
      # @return [Hash, nil] the stored action prompt definition
      def action_prompt_for(action_name)
        action_prompt_list.find { |prompt| prompt["name"] == action_name.to_s }
      end

      # The system instructions an action executes under.
      #
      # Named actions stack their prompt below the agent's base instructions
      # rather than replacing them, so an action inherits the agent's persona
      # and adds a job to it. The default action is the base instructions alone.
      #
      # @param action_name [String, Symbol, nil]
      # @return [String, nil] nil when neither part has content
      def composed_instructions_for(action_name)
        action = action_prompt_for(action_name)
        [ instructions, action&.dig("prompt") ].map(&:presence).compact.join("\n\n").presence
      end

      # The configuration as it stands right now, for writing into a version.
      #
      # Only attributes the model actually has are captured, so a host that
      # trimmed columns it does not use still snapshots cleanly.
      #
      # @return [Hash{Symbol => Object}]
      def configuration_snapshot
        SNAPSHOT_FIELDS.each_with_object({}) do |field, snapshot|
          snapshot[field.to_sym] = self[field] if has_attribute?(field)
        end
      end

      # Rolls the agent's behavior back to a stored version.
      #
      # Only {VERSIONED_FIELDS} are written — a rollback restores how the agent
      # behaves, not what it is called. Because those are exactly the fields the
      # versioning callback watches, a successful restore writes a new version
      # of its own: history moves forward, it does not rewind.
      #
      # @param version [#configuration_snapshot]
      # @return [Boolean] true
      # @raise [ActiveRecord::RecordInvalid] when the restored configuration is invalid
      def restore_from_version!(version)
        snapshot = (version.configuration_snapshot || {}).to_h.stringify_keys

        attributes = VERSIONED_FIELDS.each_with_object({}) do |field, restored|
          next unless has_attribute?(field)

          # A snapshot taken before a column existed restores that column to its
          # default rather than to NULL: v1 predates action_prompts, and rolling
          # back to v1 has to clear them — but into the empty collection the
          # column defaults to, which readers can still iterate, not `nil`.
          restored[field] = snapshot.key?(field) ? snapshot[field] : self.class.column_defaults[field]
        end

        update!(attributes)
      end

      # @return [ActiveRecord::Base, nil] the highest-numbered version
      def latest_version
        return nil unless version_model

        agent_versions.order(version_number: :desc).first
      end

      # @return [Integer] how many versions exist
      def version_count
        return 0 unless version_model

        agent_versions.count
      end

      # Whether edits to this agent are recorded as versions.
      #
      # False for observed agents. Their configuration is not authored here —
      # the telemetry registrar rewrites it from every ingest batch — so
      # versioning them would fill the history with revisions nobody made, and
      # there is nothing to roll back to anyway: the source of truth is the
      # other application's code.
      #
      # Also false when the host generated the agent model but not the version
      # model, which is a supported install that simply keeps no history.
      #
      # @return [Boolean]
      def versioned?
        return false if respond_to?(:observed?) && observed?

        !version_model.nil?
      end

      # Maps each historical instructions digest to the first version that
      # introduced it, so run cohorts can be labelled with real agent versions
      # ("v3") instead of raw hashes.
      #
      # @return [Hash{String => String}] digest to version label
      def instructions_digest_versions
        return {} unless version_model

        agent_versions.order(:version_number).each_with_object({}) do |version, map|
          snapshot = (version.configuration_snapshot || {}).to_h.stringify_keys
          base = snapshot["instructions"]
          label = "v#{version.version_number}"

          digest = SolidAgent::RunFingerprint.digest(base)
          map[digest] ||= label if digest

          # Named actions run under composed instructions, so their runs carry
          # a different digest per action for the same version.
          Array(snapshot["action_prompts"]).each do |action|
            next unless action.is_a?(Hash)

            composed = [ base, action["prompt"] ].map(&:presence).compact.join("\n\n")
            composed_digest = SolidAgent::RunFingerprint.digest(composed)
            map[composed_digest] ||= label if composed_digest
          end
        end
      end

      # Enqueues an asynchronous run of this agent.
      #
      # @param input_prompt [String]
      # @param action [String, Symbol, nil] a named action; unknown names fall
      #   back to the default action
      # @param params [Hash] arbitrary input parameters recorded on the run
      # @return [ActiveRecord::Base] the pending run
      # @raise [SolidAgent::Error] when no execution job is configured
      #
      # @example
      #   run = agent.execute("Summarize this", action: "summarize", document_id: 7)
      #   run.status #=> "pending"
      def execute(input_prompt, action: nil, **params)
        job = SolidAgent.execution_job
        unless job
          raise SolidAgent::Error,
                "#{SolidAgent.execution_job_class} is not defined, so #{self.class} cannot enqueue a run. " \
                "Set SolidAgent.execution_job_class to the job you use, or call #test_execute to run inline."
        end

        run = create_run(input_prompt, action: action, params: params, status: :pending)
        job.perform_later(run.id)
        run
      end

      # Runs this agent inline and records the result.
      #
      # Execution itself is the host's: building a runnable agent from stored
      # provider/model/instructions is activeagent's job, not a persistence
      # gem's, so the work goes through {SolidAgent.run_executor}. Everything
      # here is bookkeeping around it.
      #
      # Failures are recorded on the run rather than raised — including a
      # missing executor. The run row is the audit trail, and "this run could
      # not be executed" is a fact about the run worth persisting; the
      # directive message from the unconfigured seam lands in +error_message+.
      #
      # @param input_prompt [String]
      # @param action [String, Symbol, nil]
      # @param params [Hash]
      # @return [ActiveRecord::Base] the completed or failed run
      #
      # @example Wiring the executor once, in an initializer
      #   SolidAgent.run_executor = ->(agent, run) { AgentExecutionService.call(agent, run) }
      def test_execute(input_prompt, action: nil, **params)
        run = create_run(input_prompt, action: action, params: params,
                         status: :running, started_at: Time.current)

        begin
          result = SolidAgent.run_executor.call(self, run)
          # The executor is host code and may hand back string keys (a JSON
          # round trip, an HTTP client). Normalizing here keeps that from
          # silently recording a run with no output.
          record_completion(run, result.to_h.deep_symbolize_keys)
        rescue ::StandardError => error
          record_failure(run, error)
        end

        run
      end

      private

      def version_model
        SolidAgent.agent_version_model
      end

      # Closing out a run is the run record's own business — Records::AgentRun
      # merges metadata rather than replacing it, tolerates partial usage
      # numbers and instruments the status change — so this defers to the
      # lifecycle when the host's run model implements it. Writing the columns
      # here as well would give one application two subtly different endings
      # for the same run. The direct write is the floor for a plain run model
      # that carries the columns but none of the behavior.
      def record_completion(run, result)
        usage = result[:usage] || {}

        if run.respond_to?(:finish!)
          return run.finish!(
            output: result[:output],
            metadata: result[:metadata] || {},
            input_tokens: usage[:input_tokens],
            output_tokens: usage[:output_tokens],
            total_tokens: usage[:total_tokens]
          )
        end

        run.update!(
          output: result[:output],
          output_metadata: result[:metadata],
          status: :complete,
          completed_at: Time.current,
          duration_ms: elapsed_ms(run.started_at),
          input_tokens: usage[:input_tokens],
          output_tokens: usage[:output_tokens],
          total_tokens: usage[:total_tokens]
        )
      end

      def record_failure(run, error)
        return run.fail!(error) if run.respond_to?(:fail!)

        run.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: error.message,
          error_backtrace: error.backtrace&.first(10)&.join("\n")
        )
      end

      # Runs are created through the configured model's own columns: the run
      # schema and the agent schema drift independently once a host starts
      # editing generated migrations, and a run is not worth failing over an
      # attribute the host chose not to keep.
      def create_run(input_prompt, action:, params:, status:, started_at: nil)
        attributes = {
          "input_prompt" => input_prompt,
          "action_name" => normalized_action(action),
          "input_params" => params,
          "status" => status,
          "trace_id" => SecureRandom.uuid,
          "started_at" => started_at
        }.compact

        agent_runs.create!(attributes.slice(*agent_runs.klass.column_names))
      end

      def elapsed_ms(started_at)
        return nil unless started_at

        ((Time.current - started_at) * 1000).to_i
      end

      # Unknown action names fall back to the default rather than failing the
      # run: an action can be renamed between enqueue and execution.
      def normalized_action(action)
        action = action.to_s.presence
        action if action && available_actions.include?(action)
      end

      def action_prompt_list
        list = has_attribute?(:action_prompts) ? action_prompts : nil
        list.is_a?(Array) ? list.select { |prompt| prompt.is_a?(Hash) } : []
      end

      def generate_slug
        return if slug.present?

        base_slug = name.to_s.parameterize
        self.slug = base_slug

        # Probing the same scope the uniqueness validation uses — the platform
        # model probes globally, which hands the second tenant to register
        # "Support Bot" a `support-bot-1` even though the DB index
        # (owner column + slug) had `support-bot` free for them.
        counter = 1
        while slug_taken?
          self.slug = "#{base_slug}-#{counter}"
          counter += 1
        end
      end

      def slug_must_be_unique_for_owner
        return if slug.blank?

        errors.add(:slug, :taken) if slug_taken?
      end

      # Uniqueness is per owner, matching the (owner column, slug) unique index.
      # `for_owner` is what makes that portable: it narrows to this record's
      # owner where the host stores one, and no-ops into global uniqueness
      # where it does not.
      def slug_taken?
        scope = self.class.where(slug: slug)
        scope = scope.where.not(id: id) if persisted?
        scope = scope.for_owner(self[self.class.owner_foreign_key]) if self.class.respond_to?(:owner_foreign_key)
        scope.exists?
      end

      def create_initial_version
        agent_versions.create!(
          version_number: 1,
          change_summary: "Initial creation",
          configuration_snapshot: configuration_snapshot
        )
      end

      def configuration_changed?
        return false unless versioned?

        changed_versioned_fields.any?
      end

      def create_version_on_config_change
        agent_versions.create!(
          version_number: (latest_version&.version_number || 0) + 1,
          change_summary: "Updated: #{changed_versioned_fields.join(', ')}",
          configuration_snapshot: configuration_snapshot
        )
      end

      def changed_versioned_fields
        saved_changes.keys & VERSIONED_FIELDS
      end

      def action_prompts_must_be_well_formed
        return unless has_attribute?(:action_prompts)
        return if action_prompts.blank?

        unless action_prompts.is_a?(Array) && action_prompts.all? { |prompt| prompt.is_a?(Hash) }
          errors.add(:action_prompts, "must be a list of action definitions")
          return
        end

        names = action_prompts.map { |prompt| prompt["name"].to_s }
        names.each do |action_name|
          unless action_name.match?(/\A[a-z][a-z0-9_]*\z/)
            errors.add(:action_prompts, "action name '#{action_name}' must be snake_case")
          end

          if action_name == DEFAULT_ACTION
            errors.add(:action_prompts, "'#{DEFAULT_ACTION}' is the built-in default action")
          end
        end

        errors.add(:action_prompts, "action names must be unique") if names.uniq.size != names.size
      end
    end
  end
end

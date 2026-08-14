# frozen_string_literal: true

module SolidAgent
  # Behavior for the agent-configuration records: the agent itself, its version
  # history, the templates it can be created from, and its runs.
  #
  # The gem ships behavior only. The model classes are host-owned — generated
  # into +app/models+ by `rails generate solid_agent:agents` — and the gem
  # never defines or requires the +Agent+, +AgentVersion+, +AgentTemplate+ or
  # +AgentRun+ constants. That is deliberate, for three reasons:
  #
  # * ActiveAgent's dashboard cannot depend on solid_agent — solid_agent
  #   already depends on activeagent, so the reverse edge would be a cycle.
  #   Naming the models with configurable strings and resolving them at call
  #   time is what lets both the dashboard and a plain host app read the same
  #   tables without either gem requiring the other.
  # * Engine-namespacing them as +SolidAgent::Agent+ would make
  #   +isolate_namespace+ resolve the table to +solid_agent_agents+, and would
  #   invalidate the +contextable_type: "Agent"+ strings already persisted in
  #   production +agent_contexts+ rows.
  # * Agent configuration is the thing applications most want to extend. A
  #   host-owned model can be edited; a gem-owned one can only be monkey-patched.
  #
  # @example Resolving the configured model
  #   SolidAgent.agent_model            #=> Agent
  #   SolidAgent.agent_model_name       #=> "Agent"
  #   SolidAgent.records_installed?     #=> true
  #
  # @example Pointing at differently-named models
  #   SolidAgent.configure do |config|
  #     config.agent_class = "Ai::Assistant"
  #     config.agent_run_class = "Ai::AssistantRun"
  #   end
  module Records
    # Model names the gem resolves lazily, and their defaults.
    MODELS = {
      agent_class: "Agent",
      agent_version_class: "AgentVersion",
      agent_template_class: "AgentTemplate",
      agent_run_class: "AgentRun"
    }.freeze
  end

  class << self
    Records::MODELS.each_key { |name| attr_writer name }

    Records::MODELS.each do |name, default|
      # Configured class name, as a String. Never constantized at load time —
      # host models are autoloaded, and touching them during gem load either
      # deadlocks the Rails loader or pins a stale class across a reload.
      define_method(name) { instance_variable_get(:"@#{name}") || default }

      # The resolved class, or nil when the host has not generated it.
      #
      # @return [Class, nil]
      reader = name.to_s.sub(/_class\z/, "_model")
      define_method(reader) { public_send(name).to_s.safe_constantize }

      # The resolved class, raising a directive error when absent.
      #
      # @raise [SolidAgent::Error]
      define_method("#{reader}!") do
        public_send(reader) ||
          raise(Error, "#{public_send(name)} is not defined. Run `rails generate solid_agent:agents` " \
                       "to create it, or set SolidAgent.#{name} to the model you use instead.")
      end
    end

    # Whether the agent-records models are present and backed by tables.
    #
    # Consumers that must degrade gracefully — ActiveAgent's dashboard being
    # the motivating one — check this before touching the models. It answers
    # false both when the constant is missing and when the migration has not
    # run, because a defined model over a missing table fails later and less
    # legibly.
    #
    # @return [Boolean]
    def records_installed?
      model = agent_model
      return false unless model

      model.respond_to?(:table_exists?) && model.table_exists?
    rescue ::StandardError
      # A connection that is not established yet is not an error worth raising
      # from a predicate whose whole job is to be safe to call.
      false
    end

    # Executes an agent record and returns its result.
    #
    # Running an agent from a persisted configuration means building a class
    # from stored provider/model/instructions and driving it — execution
    # concerns, which belong to activeagent and to the host, not to a
    # persistence gem. So the gem defines the seam and the host fills it.
    #
    # The callable receives +(agent_record, run)+ and must return a Hash with
    # +:output+ and optionally +:metadata+ and +:usage+.
    #
    # @example
    #   SolidAgent.run_executor = ->(agent_record, run) { AgentExecutionService.call(agent_record, run) }
    #
    # @return [#call]
    def run_executor
      @run_executor ||= lambda do |agent_record, _run|
        raise Error, "No SolidAgent.run_executor is configured, so #{agent_record.class} cannot be executed. " \
                     "Set SolidAgent.run_executor to a callable taking (agent_record, run) and returning " \
                     "{ output:, metadata:, usage: }."
      end
    end

    attr_writer :run_executor

    # Job class enqueued by asynchronous execution, resolved at call time.
    #
    # @return [String]
    def execution_job_class
      @execution_job_class || "AgentExecutionJob"
    end

    attr_writer :execution_job_class

    # @return [Class, nil]
    def execution_job = execution_job_class.to_s.safe_constantize

    # Resets every records-layer configuration knob. Test support.
    #
    # @return [void]
    def reset_records_configuration!
      Records::MODELS.each_key { |name| instance_variable_set(:"@#{name}", nil) }
      @run_executor = nil
      @execution_job_class = nil
    end
  end
end

# The concerns load after the seam above, so a `belongs_to` reading
# SolidAgent.agent_class from an `included do` block can never outrun the
# reader that answers it.
#
# They are required eagerly, and that is safe precisely because none of them
# touches an ActiveRecord API at load time: every `belongs_to`, `enum`,
# `validates` and `scope` lives inside an `included do` or `class_methods`
# block, which Ruby stores as a block and runs only when a host model includes
# the concern. So `require "solid_agent"` in a process with no ActiveRecord —
# a rake task, a manifest-only consumer — defines these modules and loads
# nothing else. If a concern ever needs an AR constant at load time, it belongs
# behind an `ActiveSupport.on_load(:active_record)` hook, not in this list.
require_relative "records/ownable"
require_relative "records/agent"
require_relative "records/agent_version"
require_relative "records/agent_template"
require_relative "records/agent_run"

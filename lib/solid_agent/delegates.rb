# frozen_string_literal: true

module SolidAgent
  module Delegation
    # Raised when a delegation budget is exhausted and the policy is +:raise+.
    class BudgetExceededError < SolidAgent::Error
      # @return [Budget::Violation]
      attr_reader :violation
      # @return [Definition]
      attr_reader :definition

      def initialize(violation, definition:)
        @violation  = violation
        @definition = definition

        super("#{definition.agent_class}##{definition.action} exceeded its delegation budget " \
              "(#{violation.limit}: #{violation.used} of #{violation.allowed} used)")
      end
    end

    # Raised when a delegated call exceeds its timeout and the policy is +:raise+.
    class TimeoutError < SolidAgent::Error; end

    # Raised when a sub-agent's output does not satisfy its declared +returns+
    # schema and the policy is +:raise+.
    class InvalidResultError < SolidAgent::Error; end
  end
end

require_relative "delegation/schema"
require_relative "delegation/budget"
require_relative "delegation/backend"
require_relative "delegation/contract"
require_relative "delegation/runner"

module SolidAgent
  # Agent-as-tool delegation: hand part of a job to another agent.
  #
  # A tool is a Ruby method the model can call. A *delegation* is another agent
  # the model can call — same mechanism, but the callee has its own
  # instructions, its own templates, its own model, and its own budget. That
  # separation is what makes the pattern worth having: a specialist agent stays
  # specialist, and the generalist orchestrating it never inherits its prompt.
  #
  # Delegation has three moving parts, each declared where it belongs:
  #
  # * **The contract** lives on the sub-agent, next to the action it describes.
  #   Callers say which agent they want; they never restate its parameters.
  # * **The budget** lives at the call site, because only the caller knows what
  #   the work is worth. Exceeding it returns a structured result the model can
  #   reason about, not an exception that ends the conversation.
  # * **The backend** lives at the call site too, so the same sub-agent can run
  #   on a cheap local model in one parent and a frontier model in another
  #   without either agent's code changing.
  #
  # Like every other SolidAgent concern, this one is opt-in — both the agent
  # exposing work and the agent delegating it include it.
  #
  # @example Declaring a sub-agent's contract
  #   class SummarizerAgent < ApplicationAgent
  #     include SolidAgent::Delegates
  #
  #     generate_with :openai, model: "gpt-4o-mini"
  #
  #     delegation :summarize, description: "Condense a document into key points" do
  #       string  :text, required: true, description: "Full document text"
  #       integer :limit, description: "Maximum number of key points to return"
  #
  #       returns do
  #         string :summary, required: true, description: "One-paragraph summary"
  #         array  :points, of: :string, required: true, description: "The key points"
  #       end
  #     end
  #
  #     def summarize(text:, limit: 5)
  #       prompt(message: "Summarize in #{limit} points: #{text}")
  #     end
  #   end
  #
  # @example Delegating to it
  #   class ResearchAgent < ApplicationAgent
  #     include SolidAgent::Delegates
  #
  #     generate_with :openai, model: "gpt-4o"
  #
  #     delegation_budget max_calls: 8, max_duration: 60
  #
  #     delegate_to SummarizerAgent, budget: { max_calls: 3, timeout: 20 }
  #     delegate_to FactCheckAgent, as: :verify, backend: { provider: :anthropic, model: "claude-haiku-4-5" }
  #
  #     def research(topic:)
  #       prompt(message: "Research #{topic}. Summarize sources before citing them.",
  #              tools: delegated_tools)
  #     end
  #   end
  #
  # @see SolidAgent::Delegation::Contract
  # @see SolidAgent::Delegation::Budget
  # @see SolidAgent::Delegation::Backend
  module Delegates
    extend ActiveSupport::Concern

    included do
      # Contracts this agent exposes to callers, keyed by action.
      class_attribute :delegation_contracts, instance_accessor: false, default: {}.freeze

      # Sub-agents this agent delegates to, keyed by tool name.
      class_attribute :delegations, instance_accessor: false, default: {}.freeze

      # Budget covering *all* delegated work in one generation.
      class_attribute :_delegation_budget, instance_accessor: false, default: Delegation::Budget.new

      # Delegated generations inherit the parent's trace id so a delegation
      # tree reads as one trace. ActiveAgent mints its trace id inside
      # prepare_prompt_parameters without writing it back, so it is seeded
      # here — before_generation runs ahead of that, and is public API.
      before_generation :seed_delegation_trace_id if respond_to?(:before_generation)
    end

    class_methods do
      # Declares what this agent exposes to callers: one action, its inputs,
      # and optionally the shape of what it returns.
      #
      # The description is the only thing a calling model reads before deciding
      # whether to hand work over — write it for someone who has never seen the
      # code.
      #
      # @param action [Symbol, String] the action a caller invokes
      # @param description [String] what the action does
      # @param schema [Hash, Class, Delegation::Schema, nil] inputs, when not using the block DSL
      # @param returns [Hash, Class, Delegation::Schema, nil] declared output shape
      # @param budget [Hash, Delegation::Budget, nil] default budget callers inherit
      # @param on_invalid [Symbol] +:error+ (default) or +:raise+ when output misses required keys
      # @yield input DSL; call +returns+ inside it to declare the output shape
      # @return [Delegation::Contract]
      #
      # @example
      #   delegation :translate, description: "Translate text into a target language" do
      #     string :text, required: true, description: "Text to translate"
      #     string :locale, required: true, description: "BCP 47 target locale, e.g. pt-BR"
      #   end
      def delegation(action, description: nil, schema: nil, returns: nil, budget: nil, on_invalid: :error, &block)
        contract = Delegation::Contract.new(
          action: action, description: description, schema: schema,
          returns: returns, budget: budget, on_invalid: on_invalid, &block
        )

        self.delegation_contracts = delegation_contracts.merge(contract.action => contract).freeze

        contract
      end

      # Exposes another agent to this agent's model as a tool.
      #
      # With no options, every contract the sub-agent declares becomes a tool.
      # Narrow that with +only:+/+except:+, rename with +as:+, or declare a
      # contract inline with +action:+ when you don't own the sub-agent.
      #
      # @param agent_class [Class] the sub-agent
      # @param only [Symbol, Array<Symbol>, nil] expose just these actions
      # @param except [Symbol, Array<Symbol>, nil] expose everything but these actions
      # @param as [Symbol, String, nil] tool name (defaults to the action name)
      # @param action [Symbol, String, nil] declare a contract inline for this action
      # @param description [String, nil] overrides the contract's description
      # @param schema [Hash, Class, Delegation::Schema, nil] inline contract inputs
      # @param returns [Hash, Class, Delegation::Schema, nil] inline contract outputs
      # @param backend [Symbol, Hash, Delegation::Backend, nil] provider/model to run this delegation on
      # @param budget [Hash, Delegation::Budget, nil] limits for this delegation
      # @param params [Hash, Symbol, Proc, nil] params forwarded to the sub-agent
      # @yield inline contract input DSL
      # @return [Array<Delegation::Definition>]
      # @raise [ArgumentError] on an unknown action, a name collision, or a sub-agent with no contracts
      #
      # @example Everything the sub-agent declares
      #   delegate_to SummarizerAgent
      #
      # @example One action, renamed, on a different backend, with a budget
      #   delegate_to SummarizerAgent, only: :summarize, as: :condense,
      #               backend: { model: "gpt-4o-mini" }, budget: { max_calls: 3 }
      #
      # @example An agent you don't own, described from here
      #   delegate_to Vendor::ClassifierAgent, action: :classify,
      #               description: "Classify a support ticket" do
      #     string :body, required: true, description: "Ticket body"
      #   end
      def delegate_to(agent_class, only: nil, except: nil, as: nil, action: nil, description: nil,
                      schema: nil, returns: nil, backend: nil, budget: nil, params: nil, &block)
        contracts = delegation_contracts_for(agent_class, action:, only:, except:, description:, schema:, returns:, &block)

        if (as || description) && contracts.size > 1
          raise ArgumentError, "`as:` and `description:` describe a single delegation, but #{agent_class} exposes " \
            "#{contracts.size} (#{contracts.map(&:action).join(", ")}). Narrow it with `only:` first."
        end

        contracts.map do |contract|
          define_delegation Delegation::Definition.new(
            agent_class: agent_class, contract: contract, tool_name: as,
            description: description, backend: backend, budget: budget, params: params
          )
        end
      end

      # Budget covering every delegation this agent makes in one generation.
      #
      # Per-delegation budgets still apply; a call has to clear both. Called
      # without arguments it reads the current budget.
      #
      # @param limits [Hash] see {Delegation::Budget}
      # @return [Delegation::Budget]
      #
      # @example
      #   delegation_budget max_calls: 10, max_duration: 60, max_cost: 0.25
      def delegation_budget(**limits)
        self._delegation_budget = _delegation_budget.merge(Delegation::Budget.build(limits)) if limits.any?

        _delegation_budget
      end

      # Tool definitions for this agent's delegations, in ActiveAgent's common
      # tools format.
      #
      # @param filter [nil, true, false, Symbol, Array<Symbol>] which delegations to include
      # @return [Array<Hash>]
      def delegated_tools(filter = nil)
        delegations_for(filter).map(&:to_tool)
      end

      # @param filter [nil, true, false, Symbol, Array<Symbol>]
      # @return [Array<Delegation::Definition>]
      def delegations_for(filter = nil)
        case filter
        when nil, true then delegations.values
        when false     then []
        else
          names = Array(filter).map(&:to_sym)
          unknown = names - delegations.keys
          raise ArgumentError, "Unknown #{"delegation".pluralize(unknown.size)}: #{unknown.join(", ")}. " \
            "This agent delegates to: #{delegations.keys.join(", ").presence || "(none)"}" if unknown.any?

          delegations.values_at(*names)
        end
      end

      # Merges delegated tools into every action automatically, instead of
      # requiring +tools: delegated_tools+ at each call site.
      #
      # This is opt-in because it works by prepending ActiveAgent's private
      # +prepare_prompt_parameters+ — convenient, but coupled to an internal
      # method that carries no compatibility guarantee across ActiveAgent
      # releases. The explicit form has no such coupling; prefer it unless you
      # have many actions that all delegate.
      #
      # @return [void]
      #
      # @example
      #   class ResearchAgent < ApplicationAgent
      #     include SolidAgent::Delegates
      #     auto_delegate!
      #
      #     delegate_to SummarizerAgent
      #
      #     def research(topic:)
      #       prompt(message: "Research #{topic}") # delegated tools merged for you
      #     end
      #   end
      def auto_delegate!
        return if @_auto_delegate

        @_auto_delegate = true
        prepend AutoDelegation
      end

      private

      # Registers a definition and the tool method the provider routes to.
      #
      # @param definition [Delegation::Definition]
      # @return [Delegation::Definition]
      def define_delegation(definition)
        assert_available_tool_name!(definition)

        self.delegations = delegations.merge(definition.tool_name => definition).freeze

        tool_name = definition.tool_name
        define_method(tool_name) do |**arguments|
          perform_delegation(tool_name, **arguments)
        end

        definition
      end

      # @param definition [Delegation::Definition]
      # @raise [ArgumentError]
      def assert_available_tool_name!(definition)
        name = definition.tool_name
        return if delegations.key?(name) # re-declaring a delegation is a deliberate override

        if method_defined?(name) || private_method_defined?(name)
          raise ArgumentError, "#{self} already responds to ##{name}, so it cannot also be the tool name for " \
            "#{definition.agent_class}##{definition.action}. Rename it with `as:`."
        end
      end

      # @return [Array<Delegation::Contract>]
      def delegation_contracts_for(agent_class, action:, only:, except:, description:, schema:, returns:, &block)
        assert_agent_class!(agent_class)

        if action
          assert_action!(agent_class, action)

          return [ Delegation::Contract.new(
            action: action, description: description, schema: schema, returns: returns, &block
          ) ]
        end

        assert_declares_contracts!(agent_class)
        contracts = agent_class.delegation_contracts.values

        if contracts.empty?
          raise ArgumentError, "#{agent_class} does not declare any delegations. Add " \
            "`delegation :action_name, description: \"...\"` to it, or declare one here with " \
            "`delegate_to #{agent_class}, action: :action_name, description: \"...\"`."
        end

        contracts = filter_contracts(contracts, only: only, except: except, agent_class: agent_class)
        contracts.each { |contract| assert_action!(agent_class, contract.action) }
        contracts
      end

      # @return [Array<Delegation::Contract>]
      def filter_contracts(contracts, only:, except:, agent_class:)
        selected = contracts

        if only
          names = Array(only).map(&:to_sym)
          assert_declared!(agent_class, names, contracts)
          selected = selected.select { |contract| names.include?(contract.action) }
        end

        if except
          names = Array(except).map(&:to_sym)
          assert_declared!(agent_class, names, contracts)
          selected = selected.reject { |contract| names.include?(contract.action) }
        end

        raise ArgumentError, "No delegations left on #{agent_class} after applying only:/except:" if selected.empty?

        selected
      end

      # @raise [ArgumentError]
      def assert_declared!(agent_class, names, contracts)
        unknown = names - contracts.map(&:action)
        return if unknown.empty?

        raise ArgumentError, "#{agent_class} does not declare #{"delegation".pluralize(unknown.size)} " \
          "#{unknown.join(", ")}. It declares: #{contracts.map(&:action).join(", ")}"
      end

      # @raise [ArgumentError]
      def assert_agent_class!(agent_class)
        raise ArgumentError, "delegate_to expects an agent class, got #{agent_class.inspect}" unless agent_class.is_a?(Class)
        return unless defined?(::ActiveAgent::Base)
        return if agent_class < ::ActiveAgent::Base

        raise ArgumentError, "delegate_to expects an ActiveAgent::Base subclass, got #{agent_class}"
      end

      # @raise [ArgumentError]
      def assert_declares_contracts!(agent_class)
        return if agent_class.respond_to?(:delegation_contracts)

        raise ArgumentError, "#{agent_class} cannot declare delegations because it does not include " \
          "SolidAgent::Delegates. Add `include SolidAgent::Delegates` to it, or declare the contract here " \
          "with `delegate_to #{agent_class}, action: :action_name, description: \"...\"`."
      end

      # @raise [ArgumentError]
      def assert_action!(agent_class, action)
        return if agent_class.method_defined?(action) || agent_class.private_method_defined?(action)

        raise ArgumentError, "#{agent_class} does not define ##{action}, so it cannot be delegated to."
      end
    end

    # Tool definitions for this agent's delegations.
    #
    # Pass it to +prompt+ the same way {SolidAgent::HasTools#tools} is passed:
    #
    #   prompt(message: "...", tools: delegated_tools)
    #   prompt(message: "...", tools: delegated_tools(:summarize))
    #   prompt(message: "...", tools: tools + delegated_tools)
    #
    # @param filter [nil, true, false, Symbol, Array<Symbol>] which delegations to include
    # @return [Array<Hash>]
    def delegated_tools(*filter)
      self.class.delegated_tools(filter.length <= 1 ? filter.first : filter)
    end

    # Ledger covering every delegation made during this generation.
    #
    # @return [Delegation::Ledger]
    def delegation_ledger
      @_delegation_ledger ||= Delegation::Ledger.new
    end

    # Ledger for a single delegation during this generation.
    #
    # @param tool_name [Symbol, String]
    # @return [Delegation::Ledger]
    def delegation_ledger_for(tool_name)
      delegation_ledgers[tool_name.to_sym] ||= Delegation::Ledger.new
    end

    # @return [Hash{Symbol => Delegation::Ledger}] per-delegation ledgers
    def delegation_ledgers
      @_delegation_ledgers ||= {}
    end

    # Runs a delegated call. Providers reach this through the tool method
    # {ClassMethods#delegate_to} defines.
    #
    # @param tool_name [Symbol, String]
    # @param arguments [Hash]
    # @return [Object]
    def perform_delegation(tool_name, **arguments)
      definition = self.class.delegations[tool_name.to_sym]
      raise ArgumentError, "#{self.class} has no delegation named #{tool_name}" unless definition

      Delegation::Runner.new(definition, owner: self).call(**arguments)
    end

    private

    # @return [void]
    def seed_delegation_trace_id
      prompt_options[:trace_id] ||= SecureRandom.uuid
    end

    # Merges declared delegations into the tools the provider is given.
    #
    # Only installed by {ClassMethods#auto_delegate!}. Wraps
    # +prepare_prompt_parameters+ from the outside — reading its result rather
    # than reaching into its body — so the coupling is to the method's return
    # value, not its implementation.
    #
    # @api private
    module AutoDelegation
      private

      # @return [Hash]
      def prepare_prompt_parameters
        parameters = super
        filter     = prompt_options[:delegations]
        parameters.delete(:delegations)

        tools = self.class.delegated_tools(filter)
        return parameters if tools.empty?

        declared = Array(parameters[:tools])
        names    = declared.filter_map { |tool| (tool[:name] || tool["name"]).to_s if tool.is_a?(Hash) }

        parameters[:tools] = declared + tools.reject { |tool| names.include?(tool[:name]) }
        parameters
      end
    end
  end
end

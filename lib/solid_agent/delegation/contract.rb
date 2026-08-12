# frozen_string_literal: true

require "delegate"

module SolidAgent
  module Delegation
    # What a sub-agent promises: one action, its inputs, and optionally the
    # shape of what it returns.
    #
    # The contract is declared on the sub-agent itself, next to the action it
    # describes, so a delegation stays correct when the action changes. Callers
    # then say only which agent they want — they never restate its parameters.
    #
    # @example
    #   class SummarizerAgent < ApplicationAgent
    #     delegation :summarize, description: "Condense a document into key points" do
    #       string  :text, required: true, description: "Full document text"
    #       integer :limit, description: "Maximum number of key points"
    #
    #       returns do
    #         string :summary, required: true, description: "One-paragraph summary"
    #         array  :points, of: :string, required: true, description: "Key points"
    #       end
    #     end
    #
    #     def summarize(text:, limit: 5)
    #       prompt(message: text, limit: limit)
    #     end
    #   end
    class Contract
      # What to do when a sub-agent's output does not satisfy its +returns+ schema.
      #
      # +:error+ — hand the calling model a structured error so it can retry or
      #            route around the failure (default).
      # +:raise+ — raise {InvalidResultError} and abort the generation.
      INVALID_POLICIES = %i[error raise].freeze

      # @return [Symbol] the sub-agent action this contract describes
      attr_reader :action
      # @return [String] what the action does, written for the calling model
      attr_reader :description
      # @return [Schema] declared inputs
      attr_reader :schema
      # @return [Schema, nil] declared output shape, when the action returns structured data
      attr_reader :returns
      # @return [Budget] default budget suggested by the sub-agent
      attr_reader :budget
      # @return [Symbol] :error or :raise
      attr_reader :on_invalid

      # @param action [Symbol, String]
      # @param description [String]
      # @param schema [Schema, Hash, Class, nil] inputs, or nil to use the block DSL
      # @param returns [Schema, Hash, Class, nil] declared output shape
      # @param budget [Budget, Hash, nil] default budget for callers
      # @param on_invalid [Symbol] :error or :raise
      # @yield input DSL; may also call +returns+ to declare the output shape
      def initialize(action:, description:, schema: nil, returns: nil, budget: nil, on_invalid: :error, &block)
        @action      = action.to_sym
        @description = description
        @returns     = returns && Schema.build(returns)
        @budget      = Budget.build(budget)
        @on_invalid  = on_invalid.to_sym

        unless INVALID_POLICIES.include?(@on_invalid)
          raise ArgumentError, "Unknown delegation on_invalid policy #{@on_invalid.inspect}. " \
            "Valid policies: #{INVALID_POLICIES.join(", ")}"
        end

        raise ArgumentError, "A delegation needs a description — it is the only thing the calling model reads" if @description.blank?

        @schema = Schema.build(schema)

        if block
          dsl = DSL.new(self, @schema)
          block.arity == 1 ? block.call(dsl) : dsl.instance_eval(&block)
        end
      end

      # @return [Boolean]
      def structured?
        returns.present?
      end

      # Sets the declared output shape. Used by the DSL's +returns+ helper.
      #
      # @param schema [Schema]
      # @return [Schema]
      # @api private
      def returns=(schema)
        @returns = schema
      end

      # Wraps the input schema DSL so that +returns+ inside a delegation block
      # declares the *output* shape rather than an input property.
      #
      # @api private
      class DSL < SimpleDelegator
        # @param contract [Contract]
        # @param schema [Schema]
        def initialize(contract, schema)
          @contract = contract
          super(schema)
        end

        # Declares the shape the action returns.
        #
        # @param source [Schema, Hash, Class, nil]
        # @yield output DSL
        # @return [Schema]
        def returns(source = nil, &block)
          @contract.returns = Schema.build(source, &block)
        end
      end
    end

    # A sub-agent bound into a calling agent as a tool.
    #
    # Pairs the sub-agent's {Contract} — what it accepts and returns — with the
    # decisions that belong to the caller: what to call it, what it may spend,
    # and which backend serves it.
    class Definition
      # @return [Class] the sub-agent class
      attr_reader :agent_class
      # @return [Contract]
      attr_reader :contract
      # @return [Symbol] the tool name exposed to the calling model
      attr_reader :tool_name
      # @return [String]
      attr_reader :description
      # @return [Backend]
      attr_reader :backend
      # @return [Budget]
      attr_reader :budget
      # @return [Hash, Symbol, Proc, nil] params forwarded to the sub-agent
      attr_reader :params

      # @param agent_class [Class]
      # @param contract [Contract]
      # @param tool_name [Symbol, String, nil] defaults to the contract's action
      # @param description [String, nil] overrides the contract's description
      # @param backend [Backend, Symbol, Hash, nil]
      # @param budget [Budget, Hash, nil] merged over the contract's default budget
      # @param params [Hash, Symbol, Proc, nil]
      def initialize(agent_class:, contract:, tool_name: nil, description: nil, backend: nil, budget: nil, params: nil)
        @agent_class = agent_class
        @contract    = contract
        @tool_name   = (tool_name || contract.action).to_sym
        @description = description.presence || contract.description
        @backend     = Backend.build(backend)
        @budget      = contract.budget.merge(Budget.build(budget))
        @params      = params
      end

      # @return [Symbol] the sub-agent action invoked
      def action = contract.action

      # @return [Schema] declared inputs
      def schema = contract.schema

      # @return [Schema, nil] declared outputs
      def returns = contract.returns

      # @return [Boolean]
      def structured? = contract.structured?

      # @return [Symbol]
      def on_invalid = contract.on_invalid

      # The class a call actually instantiates, after any backend swap.
      #
      # @return [Class]
      def resolved_agent_class
        backend.agent_class_for(agent_class)
      end

      # Tool definition in ActiveAgent's common tools format.
      #
      # This is what the calling model sees — the whole point of declaring a
      # schema rather than describing the sub-agent in prose.
      #
      # @return [Hash]
      def to_tool
        {
          name: tool_name.to_s,
          description: description,
          parameters: schema.to_json_schema
        }
      end

      # Returns a copy with call-site overrides applied.
      #
      # @return [Definition]
      def with(tool_name: nil, description: nil, backend: nil, budget: nil, params: nil)
        self.class.new(
          agent_class: agent_class,
          contract: contract,
          tool_name: tool_name || self.tool_name,
          description: description || self.description,
          backend: backend || self.backend,
          budget: budget ? self.budget.merge(Budget.build(budget)) : self.budget,
          params: params || self.params
        )
      end
    end
  end
end

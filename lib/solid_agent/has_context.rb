# frozen_string_literal: true

require "digest"

# HasContext provides database-backed prompt context management for agents.
#
# This concern adds the `has_context` class method which configures an agent
# to persist its prompt context, messages, and generation results to the database.
# It works similarly to ActiveRecord associations, allowing custom naming.
#
# @example Basic usage with auto-context (contextual inferred from params)
#   class WritingAssistantAgent < ApplicationAgent
#     include SolidAgent::HasContext
#     has_context contextual: :document  # Auto-creates context from params[:document]
#
#     def improve
#       prompt  # Context automatically created before prompt
#     end
#   end
#
# @example Named context with auto-creation
#   class ChatAgent < ApplicationAgent
#     include SolidAgent::HasContext
#     has_context :conversation, contextual: :user  # Auto-loads/creates from params[:user]
#
#     def chat
#       add_conversation_user_message(params[:message])
#       prompt messages: conversation_messages
#     end
#   end
#
# @example Manual context management (contextual: false)
#   class ResearchAgent < ApplicationAgent
#     include SolidAgent::HasContext
#     has_context :research_session, contextual: false
#
#     def research
#       create_research_session(contextable: params[:project])  # Manual creation
#       prompt(tools: tools)
#     end
#   end
#
# @example Multiple contexts with different contextual params
#   class MultiModalAgent < ApplicationAgent
#     include SolidAgent::HasContext
#     has_context :conversation, contextual: :user      # Auto from params[:user]
#     has_context :analysis, contextual: :document      # Auto from params[:document]
#
#     def analyze
#       prompt  # Both contexts auto-created
#     end
#   end
#
module SolidAgent
  module HasContext
    extend ActiveSupport::Concern

    included do
      # Store all context configurations (supports multiple has_context calls)
      class_attribute :_context_configs, default: {}

      # Default context accessor for backward compatibility
      attr_accessor :generation_response
    end

    class_methods do
      # Configures database-backed context persistence for this agent.
      #
      # @param name [Symbol, nil] Name for the context (e.g., :conversation, :research_session)
      #   - nil or :context uses default naming (context, load_context, create_context)
      #   - :conversation creates conversation, load_conversation, create_conversation
      #
      # @param class_name [String, Class] The model class for storing context
      #   - Defaults to "AgentContext" for unnamed, or "{Name}Context" for named
      #
      # @param message_class [String, Class] The model class for storing messages
      #   - Defaults based on context class name
      #
      # @param generation_class [String, Class] The model class for storing generations
      #   - Defaults based on context class name
      #
      # @param auto_save [Boolean] Automatically save generation results (default: true)
      #
      # @param contextual [Symbol, false, nil] Param key for auto-context creation
      #   - Symbol: Auto-load/create context using params[contextual] (e.g., :user, :document)
      #   - false: Disable auto-context, require manual create_* or load_* calls
      #   - nil: Auto-create context without a contextable (anonymous context)
      #
      # @example Auto-context from params
      #   has_context :conversation, contextual: :user
      #
      # @example Manual context management
      #   has_context :session, contextual: false
      #
      # @example Fully customized
      #   has_context :session,
      #               class_name: "ChatSession",
      #               message_class: "ChatMessage",
      #               generation_class: "ChatGeneration",
      #               contextual: :chat_user,
      #               auto_save: false
      #
      def has_context(name = nil, class_name: nil, message_class: nil, generation_class: nil, auto_save: true, contextual: nil)
        # Normalize name
        context_name = normalize_context_name(name)

        # Infer class names based on context name
        inferred_classes = infer_class_names(context_name, class_name)

        config = {
          name: context_name,
          context_class: class_name || inferred_classes[:context],
          message_class: message_class || inferred_classes[:message],
          generation_class: generation_class || inferred_classes[:generation],
          auto_save: auto_save,
          contextual: contextual
        }

        # Store configuration
        self._context_configs = _context_configs.merge(context_name => config)

        # Define instance accessor for this context
        define_context_accessor(context_name)

        # Define helper methods
        define_context_methods(context_name)

        # Add callbacks for auto_save (only for primary/first context)
        if auto_save && _context_configs.size == 1
          after_prompt :persist_prompt_to_context
          around_generation :capture_and_persist_generation
        end

        # Add auto-context callback if contextual is not explicitly false
        if contextual != false
          after_prompt :"ensure_#{context_name}_exists"
          define_auto_context_method(context_name, contextual)
        end
      end

      private

      def normalize_context_name(name)
        case name
        when nil, :context, :contexts
          :context
        else
          name.to_s.singularize.to_sym
        end
      end

      def infer_class_names(context_name, explicit_class_name)
        if context_name == :context
          {
            context: "AgentContext",
            message: "AgentMessage",
            generation: "AgentGeneration"
          }
        elsif explicit_class_name
          # If class_name is provided, infer message/generation from it
          base = explicit_class_name.to_s.delete_suffix("Context").delete_suffix("Session")
          {
            context: explicit_class_name,
            message: "#{base}Message",
            generation: "#{base}Generation"
          }
        else
          # Infer from context_name (e.g., :conversation -> Conversation, ConversationMessage)
          base = context_name.to_s.camelize
          {
            context: base,
            message: "#{base}Message",
            generation: "#{base}Generation"
          }
        end
      end

      def define_context_accessor(context_name)
        attr_accessor context_name
      end

      def define_auto_context_method(context_name, contextual_key)
        # Define ensure_{name}_exists method that auto-creates context if not present
        define_method("ensure_#{context_name}_exists") do
          return if send(context_name).present?

          config = self.class._context_configs[context_name]
          contextual_param = config[:contextual]

          if contextual_param.is_a?(Symbol)
            # Load or create with contextable from params
            contextable_value = params[contextual_param]
            send("load_#{context_name}", contextable: contextable_value)
          else
            # Create anonymous context (no contextable)
            send("create_#{context_name}")
          end
        end
      end

      def define_context_methods(context_name)
        config_key = context_name

        # Define {name}_class method
        define_method("#{context_name}_class") do
          config = self.class._context_configs[config_key]
          instance_variable_get("@_#{context_name}_class") ||
            instance_variable_set("@_#{context_name}_class", config[:context_class].to_s.constantize)
        end

        # Define {name}_message_class method
        define_method("#{context_name}_message_class") do
          config = self.class._context_configs[config_key]
          instance_variable_get("@_#{context_name}_message_class") ||
            instance_variable_set("@_#{context_name}_message_class", config[:message_class].to_s.constantize)
        end

        # Define {name}_generation_class method
        define_method("#{context_name}_generation_class") do
          config = self.class._context_configs[config_key]
          instance_variable_get("@_#{context_name}_generation_class") ||
            instance_variable_set("@_#{context_name}_generation_class", config[:generation_class].to_s.constantize)
        end

        # Define load_{name} method
        define_method("load_#{context_name}") do |contextable: nil, context_id: nil, **options|
          ctx_class = send("#{context_name}_class")

          loaded = if context_id
            ctx_class.find(context_id)
          elsif contextable
            ctx_class.find_or_create_by!(
              contextable: contextable,
              agent_name: self.class.name,
              action_name: action_name
            ) do |ctx|
              ctx.instructions = prompt_options[:instructions] if ctx.respond_to?(:instructions=)
              ctx.options = options if ctx.respond_to?(:options=)
              ctx.trace_id = prompt_options[:trace_id] if ctx.respond_to?(:trace_id=)
            end
          else
            ctx_class.create!(
              agent_name: self.class.name,
              action_name: action_name,
              instructions: prompt_options[:instructions],
              options: options,
              trace_id: prompt_options[:trace_id]
            )
          end

          send("#{context_name}=", loaded)
        end

        # Define create_{name} method
        define_method("create_#{context_name}") do |contextable: nil, **options|
          ctx_class = send("#{context_name}_class")

          created = ctx_class.create!(
            contextable: contextable,
            agent_name: self.class.name,
            action_name: action_name,
            instructions: prompt_options[:instructions],
            options: options,
            trace_id: prompt_options[:trace_id]
          )

          send("#{context_name}=", created)
        end

        # Define {name}_messages method
        define_method("#{context_name}_messages") do
          ctx = send(context_name)
          return [] unless ctx
          ctx.messages.map(&:to_message_hash)
        end

        # Define with_{name}_messages method
        define_method("with_#{context_name}_messages") do
          msgs = send("#{context_name}_messages")
          prompt messages: msgs if msgs.any?
        end

        # Define add_{name}_message method
        define_method("add_#{context_name}_message") do |role:, content:, **attributes|
          ctx = send(context_name)
          raise SolidAgent::Error, "No #{context_name} loaded. Call load_#{context_name} or create_#{context_name} first." unless ctx

          # Build message attributes
          message_attrs = { role: role, content: content, **attributes }

          # Add provenance data if the message model supports it
          # Check via the context's message association if available
          begin
            if ctx.messages.respond_to?(:build)
              sample = ctx.messages.build
              message_attrs[:provenance] = current_provenance if sample.respond_to?(:provenance=)
              message_attrs[:content_checksum] = Digest::MD5.hexdigest(content.to_s) if sample.respond_to?(:content_checksum=)
            end
          rescue StandardError
            # Ignore if we can't check - just create without extra fields
          end

          ctx.messages.create!(**message_attrs)
        end

        # Define add_{name}_user_message method
        define_method("add_#{context_name}_user_message") do |content, **attributes|
          send("add_#{context_name}_message", role: "user", content: content, **attributes)
        end

        # Define add_{name}_assistant_message method
        define_method("add_#{context_name}_assistant_message") do |content, **attributes|
          send("add_#{context_name}_message", role: "assistant", content: content, **attributes)
        end

        # Define {name}_result method - returns the last assistant message content
        # Useful for extracting the final result to pass back to a caller's context
        define_method("#{context_name}_result") do
          ctx = send(context_name)
          return nil unless ctx
          ctx.messages.select { |m| m.role == "assistant" }.last&.content
        end

        # Define {name}_last_generation method - returns the last generation record
        define_method("#{context_name}_last_generation") do
          ctx = send(context_name)
          return nil unless ctx
          ctx.generations.last
        end

        # Define {name}_summary method - returns a hash with key context data
        # Useful for passing structured results back to a parent context
        define_method("#{context_name}_summary") do
          ctx = send(context_name)
          return nil unless ctx
          {
            id: ctx.id,
            result: send("#{context_name}_result"),
            message_count: ctx.messages.size,
            total_tokens: ctx.respond_to?(:total_tokens) ? ctx.total_tokens : nil,
            created_at: ctx.created_at,
            agent_name: ctx.agent_name,
            action_name: ctx.action_name
          }.compact
        end
      end
    end

    # === Backward compatibility methods ===
    # These delegate to the primary context (first or :context)

    def context
      primary_context_name = self.class._context_configs.keys.first || :context
      send(primary_context_name)
    end

    def context=(value)
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}=", value)
    end

    def context_class
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_class")
    end

    def message_class
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_message_class")
    end

    def generation_class
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_generation_class")
    end

    def load_context(contextable: nil, context_id: nil, **options)
      primary_context_name = self.class._context_configs.keys.first || :context
      send("load_#{primary_context_name}", contextable: contextable, context_id: context_id, **options)
    end

    def create_context(contextable: nil, **options)
      primary_context_name = self.class._context_configs.keys.first || :context
      send("create_#{primary_context_name}", contextable: contextable, **options)
    end

    def context_messages
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_messages")
    end

    def with_context_messages
      primary_context_name = self.class._context_configs.keys.first || :context
      send("with_#{primary_context_name}_messages")
    end

    def add_message(role:, content:, **attributes)
      primary_context_name = self.class._context_configs.keys.first || :context
      send("add_#{primary_context_name}_message", role: role, content: content, **attributes)
    end

    def add_user_message(content, **attributes)
      add_message(role: "user", content: content, **attributes)
    end

    def add_assistant_message(content, **attributes)
      add_message(role: "assistant", content: content, **attributes)
    end

    # Returns the last assistant message content from the primary context
    # Useful for extracting the final result to pass back to a caller
    def context_result
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_result")
    end

    # Returns the last generation record from the primary context
    def last_generation
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_last_generation")
    end

    # Returns a summary hash of the primary context
    # Useful for passing structured results back to a parent context
    def context_summary
      primary_context_name = self.class._context_configs.keys.first || :context
      send("#{primary_context_name}_summary")
    end

    # ============================================
    # Provenance & Checksums
    # ============================================

    # Generate checksum for current prompt configuration
    #
    # @return [String] MD5 hex digest
    def prompt_checksum
      data = {
        instructions: prompt_options[:instructions],
        model: prompt_options[:model],
        temperature: prompt_options[:temperature],
        tools: prompt_options[:tools]&.map { |t| t[:name] }
      }.compact
      Digest::MD5.hexdigest(data.to_json)
    end

    # Generate checksum for current context state
    #
    # @return [String, nil] MD5 hex digest or nil if no context
    def context_checksum
      return nil unless context
      Digest::MD5.hexdigest({
        context_id: context.id,
        message_count: context.messages.size,
        last_message_id: context.messages.last&.id
      }.to_json)
    end

    # Generate provenance record for current agent state
    #
    # @return [Hash] Full provenance data for tracing
    def current_provenance
      {
        agent_class: self.class.name,
        agent_checksum: agent_checksum,
        prompt_checksum: prompt_checksum,
        context_checksum: context_checksum,
        context_id: context&.id,
        action_name: action_name,
        trace_id: prompt_options[:trace_id],
        timestamp: Time.now.iso8601,
        manifest_fingerprint: manifest_fingerprint
      }.compact
    end

    # Generate checksum for the agent class configuration
    #
    # Class-level options are read defensively so provenance never raises
    # inside the (rescued) persistence path and silently drops generations.
    #
    # @return [String] MD5 hex digest
    def agent_checksum
      data = {
        class: self.class.name,
        prompt_options: class_options(:prompt_options),
        embed_options: class_options(:embed_options)
      }.compact
      Digest::MD5.hexdigest(data.to_json)
    end

    # Get manifest fingerprint if agent was built from manifest
    #
    # @return [String, nil] Fingerprint or nil
    def manifest_fingerprint
      return nil unless self.class.respond_to?(:_manifest) && self.class._manifest
      self.class._manifest.fingerprint
    end

    private

    # Class-level option hash for checksums, or nil when unavailable
    def class_options(reader)
      return nil unless self.class.respond_to?(reader)

      self.class.public_send(reader)&.except(:access_token, :api_key)
    end

    # After prompt callback - persists the rendered prompt message to context
    def persist_prompt_to_context
      return unless context

      if prompt_options[:messages].present?
        rendered_message = prompt_options[:messages].last
        content = rendered_message.is_a?(Hash) ? rendered_message[:content] : rendered_message.to_s
        add_user_message(content) if content.present?
      end
    end

    # Around callback to capture the response and persist to context
    def capture_and_persist_generation
      self.generation_response = yield
      persist_generation_to_context
      generation_response
    end

    # Persists the generation response to context
    def persist_generation_to_context
      return unless context && generation_response

      persist_tool_messages_to_context

      begin
        if generation_response.respond_to?(:message) && generation_response.message&.content.present?
          # Include provenance if the context supports it
          if context.respond_to?(:record_generation_with_provenance!)
            context.record_generation_with_provenance!(generation_response, current_provenance)
          else
            context.record_generation!(generation_response)
          end
          Rails.logger.info "[SolidAgent] Persisted generation to context #{context.id} (#{prompt_checksum[0..7]})"
        else
          Rails.logger.warn "[SolidAgent] Skipping persistence - no message content in response"
        end
      rescue => e
        Rails.logger.error "[SolidAgent] Failed to persist generation: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end

    # Overridable enrichment hook for tool persistence. Executors that run
    # tools server-side (a platform's execution service, a job) can
    # override this to return their own invocation records — an array of
    # hashes with symbol keys :tool_call_id, :name, :arguments and
    # :duration_ms (all optional) — so persisted tool messages carry the
    # call's arguments and timing, which provider response messages don't
    # include. Records are matched to response tool messages by
    # tool_call_id when both sides have one, otherwise by position.
    def tool_invocations
      []
    end

    # Persists the tool/MCP interaction stream (tool result messages from
    # the response's message stack) to the context, so conversations show
    # the full agent <-> tool exchange, not just the final assistant text.
    #
    # Requires the context model to expose add_tool_message (the install
    # generator's AgentContext does); contexts without it are skipped.
    # Messages are deduped by tool_call_id so re-persisting a shared
    # message stack (multi-turn conversations) doesn't duplicate rows.
    def persist_tool_messages_to_context
      return unless context.respond_to?(:add_tool_message)
      return unless generation_response.respond_to?(:messages)

      tool_index = -1
      Array(generation_response.messages).each do |message|
        next unless message.respond_to?(:role) && message.role.to_s == "tool"

        tool_index += 1
        tool_call_id = message.respond_to?(:tool_call_id) ? message.tool_call_id : nil
        next if tool_call_id.present? && tool_message_persisted?(tool_call_id)

        invocation = tool_invocation_for(tool_call_id, tool_index)
        # Provider tool messages often carry no name (Ollama's don't); the
        # executor's invocation record is the fallback.
        name = (message.name if message.respond_to?(:name))
        name = invocation[:name] if !name.present? && invocation

        attributes = {
          tool_call_id: tool_call_id,
          tool_name: name,
          result: (message.content if message.respond_to?(:content))
        }
        if invocation && tool_message_details_supported?
          attributes[:arguments] = invocation[:arguments]
          attributes[:duration_ms] = invocation[:duration_ms]
        end
        context.add_tool_message(**attributes)
      end
    rescue => e
      Rails.logger.error "[SolidAgent] Failed to persist tool messages: #{e.message}"
    end

    def tool_message_persisted?(tool_call_id)
      return false unless context.respond_to?(:messages)

      scope = context.messages
      scope.respond_to?(:exists?) && scope.exists?(role: "tool", tool_call_id: tool_call_id)
    end

    # Finds the executor invocation record for a response tool message —
    # by tool_call_id when the record carries one, else by position among
    # the response's tool messages.
    def tool_invocation_for(tool_call_id, index)
      invocations = Array(tool_invocations)
      return nil if invocations.empty?

      if tool_call_id.present?
        match = invocations.find { |inv| inv[:tool_call_id] && inv[:tool_call_id].to_s == tool_call_id.to_s }
        return match if match
      end
      invocations[index]
    end

    # Whether the context's add_tool_message accepts the arguments:/
    # duration_ms: enrichment keywords (older generated models don't).
    def tool_message_details_supported?
      parameters = context.method(:add_tool_message).parameters
      parameters.any? { |type, param_name| type == :keyrest || ([ :key, :keyreq ].include?(type) && param_name == :arguments) }
    rescue ::NameError
      false
    end
  end
end

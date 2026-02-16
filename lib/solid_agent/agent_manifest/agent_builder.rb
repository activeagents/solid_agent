# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # AgentBuilder generates ActiveAgent classes from Manifest definitions.
    #
    # Creates anonymous or named classes with the appropriate concerns included,
    # tools defined, and system instructions configured.
    #
    # @example Build an agent class from a manifest
    #   manifest = AgentManifest.parse("research_assistant.agent.md")
    #   klass = AgentBuilder.build(manifest)
    #   agent = klass.new
    #   agent.research(query: "Ruby concurrency")
    #
    # @example Build with a custom base class
    #   klass = AgentBuilder.build(manifest, base_class: ApplicationAgent)
    #
    # @example Build with explicit naming
    #   klass = AgentBuilder.build(manifest, class_name: "CustomResearchAgent")
    #   CustomResearchAgent.new.call
    #
    class AgentBuilder
      class << self
        # Build an agent class from a manifest
        #
        # @param manifest [Manifest] The manifest to build from
        # @param base_class [Class] Base class to inherit from
        # @param class_name [String, nil] Optional class name for constant registration
        # @param namespace [Module, nil] Optional namespace for constant registration
        # @return [Class] The generated agent class
        def build(manifest, base_class: nil, class_name: nil, namespace: nil)
          # Determine base class
          parent_class = determine_base_class(manifest, base_class)

          # Create the class
          klass = Class.new(parent_class)

          # Configure the agent
          configure_model(klass, manifest)
          configure_concerns(klass, manifest)
          configure_tools(klass, manifest)
          configure_instructions(klass, manifest)
          configure_metadata(klass, manifest)

          # Register as constant if requested
          if class_name || manifest_class_name(manifest)
            register_constant(klass, class_name || manifest_class_name(manifest), namespace)
          end

          klass
        end

        # Build and instantiate an agent from a manifest
        #
        # @param manifest [Manifest] The manifest to build from
        # @param params [Hash] Parameters to pass to the agent
        # @return [Object] The instantiated agent
        def build_instance(manifest, params: {}, **options)
          klass = build(manifest, **options)
          klass.new(params)
        end

        # Build from a file path
        #
        # @param path [String] Path to manifest file
        # @param options [Hash] Options passed to build
        # @return [Class] The generated agent class
        def build_from_file(path, **options)
          manifest = ParserRegistry.parse(path)
          build(manifest, **options)
        end

        private

        # Determine the base class for the agent
        def determine_base_class(manifest, explicit_base)
          return explicit_base if explicit_base

          # Check activeagent extension for parent class
          aa_config = manifest.extensions&.dig(:activeagent) || {}
          if aa_config[:parent_class]
            aa_config[:parent_class].to_s.constantize
          elsif defined?(ApplicationAgent)
            ApplicationAgent
          elsif defined?(ActiveAgent::Base)
            ActiveAgent::Base
          else
            # Fallback to a basic class
            Object
          end
        end

        # Configure model/provider settings
        def configure_model(klass, manifest)
          return unless manifest.model.present?

          provider, model_name = parse_model_identifier(manifest.model)

          # Set class-level configuration
          klass.class_eval do
            class_attribute :_manifest_model, default: nil
            class_attribute :_manifest_provider, default: nil
            class_attribute :_manifest_config, default: {}
          end

          klass._manifest_model = model_name
          klass._manifest_provider = provider
          klass._manifest_config = manifest.config || {}

          # If the base class supports model configuration, use it
          if klass.respond_to?(:model)
            klass.model(model_name)
          end

          if klass.respond_to?(:provider) && provider
            klass.provider(provider)
          end
        end

        # Parse model identifier into provider and model name
        def parse_model_identifier(model_string)
          if model_string.include?("/")
            parts = model_string.split("/", 2)
            [parts[0], parts[1]]
          else
            [nil, model_string]
          end
        end

        # Configure concerns based on manifest extensions
        def configure_concerns(klass, manifest)
          aa_config = manifest.extensions&.dig(:activeagent) || {}
          concerns = aa_config[:concerns] || []

          concerns.each do |concern_config|
            apply_concern(klass, concern_config)
          end

          # Auto-include HasTools if manifest defines tools
          if manifest.tools&.any? && !has_concern?(klass, SolidAgent::HasTools)
            apply_concern(klass, "has_tools")
          end
        end

        # Apply a single concern to the class
        def apply_concern(klass, concern_config)
          case concern_config
          when String, Symbol
            concern_name = concern_config.to_s
            options = {}
          when Hash
            concern_name = concern_config.keys.first.to_s
            options = concern_config.values.first || {}
          else
            return
          end

          concern_module = resolve_concern(concern_name)
          return unless concern_module

          klass.include(concern_module)

          # Call the DSL method if it exists (e.g., has_context, has_tools)
          if klass.respond_to?(concern_name)
            if options.is_a?(Hash) && options.any?
              klass.send(concern_name, **symbolize_keys(options))
            elsif options.is_a?(Array)
              klass.send(concern_name, *options)
            else
              klass.send(concern_name)
            end
          end
        end

        # Resolve a concern name to a module
        def resolve_concern(name)
          case name.to_s
          when "has_context"
            SolidAgent::HasContext
          when "has_tools"
            SolidAgent::HasTools
          when "streams_tool_updates"
            SolidAgent::StreamsToolUpdates
          else
            # Try to constantize
            begin
              name.to_s.camelize.constantize
            rescue NameError
              nil
            end
          end
        end

        # Check if a class already includes a concern
        def has_concern?(klass, concern)
          klass.included_modules.include?(concern)
        end

        # Configure tools from manifest
        def configure_tools(klass, manifest)
          return unless manifest.tools&.any?

          manifest.tools.each do |tool|
            define_tool(klass, tool) unless tool.reference?
          end

          # Store tool references for later resolution
          tool_refs = manifest.tools.select(&:reference?).map(&:ref)
          if tool_refs.any?
            klass.class_attribute :_manifest_tool_refs, default: []
            klass._manifest_tool_refs = tool_refs
          end
        end

        # Define a tool on the class
        def define_tool(klass, tool)
          return unless klass.respond_to?(:tool)

          tool_name = tool.name.to_sym
          tool_desc = tool.description
          tool_schema = tool.input_schema || {}

          klass.tool(tool_name) do
            description tool_desc if tool_desc

            # Define parameters from schema
            properties = tool_schema["properties"] || tool_schema[:properties] || {}
            required = tool_schema["required"] || tool_schema[:required] || []

            properties.each do |param_name, param_schema|
              param_opts = {
                type: param_schema["type"] || param_schema[:type] || "string",
                required: required.include?(param_name.to_s),
                description: param_schema["description"] || param_schema[:description]
              }
              param_opts[:enum] = param_schema["enum"] || param_schema[:enum] if param_schema["enum"] || param_schema[:enum]
              param_opts[:default] = param_schema["default"] || param_schema[:default] if param_schema.key?("default") || param_schema.key?(:default)

              parameter param_name.to_sym, **param_opts.compact
            end
          end

          # Define a placeholder method if it doesn't exist
          unless klass.instance_methods.include?(tool_name)
            klass.define_method(tool_name) do |**args|
              raise NotImplementedError, "Tool method '#{tool_name}' must be implemented"
            end
          end
        end

        # Configure system instructions
        def configure_instructions(klass, manifest)
          return unless manifest.instructions.present? || manifest.template.present?

          instructions = manifest.instructions || manifest.template

          klass.class_attribute :_manifest_instructions, default: nil
          klass._manifest_instructions = instructions

          # If the base class supports system instructions, set them
          if klass.respond_to?(:system_instructions)
            klass.system_instructions(instructions)
          end

          # Store template for rendering
          if manifest.template.present?
            klass.class_attribute :_manifest_template, default: nil
            klass._manifest_template = manifest.template
          end
        end

        # Configure metadata
        def configure_metadata(klass, manifest)
          klass.class_attribute :_manifest, default: nil
          klass._manifest = manifest

          klass.class_attribute :_manifest_name, default: nil
          klass._manifest_name = manifest.name

          klass.class_attribute :_manifest_version, default: nil
          klass._manifest_version = manifest.version

          klass.class_attribute :_manifest_description, default: nil
          klass._manifest_description = manifest.description
        end

        # Get class name from manifest
        def manifest_class_name(manifest)
          aa_config = manifest.extensions&.dig(:activeagent) || {}
          return aa_config[:class_name] if aa_config[:class_name]

          # Generate from manifest name
          if manifest.name.present?
            name = manifest.name.to_s.tr("-", "_").camelize
            name += "Agent" unless name.end_with?("Agent")
            name
          end
        end

        # Register the class as a constant
        def register_constant(klass, name, namespace)
          target = namespace || Object

          if target.const_defined?(name, false)
            target.send(:remove_const, name)
          end

          target.const_set(name, klass)
        end

        # Deep symbolize keys
        def symbolize_keys(hash)
          return hash unless hash.is_a?(Hash)

          hash.transform_keys(&:to_sym).transform_values do |v|
            v.is_a?(Hash) ? symbolize_keys(v) : v
          end
        end
      end
    end
  end
end

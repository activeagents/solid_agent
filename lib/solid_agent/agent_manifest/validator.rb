# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # Validator provides comprehensive validation for Manifests.
    #
    # Goes beyond ActiveModel validations to check semantic correctness,
    # tool definitions, schema validity, and cross-field consistency.
    #
    # @example Validate a manifest
    #   errors = Validator.validate(manifest)
    #   if errors.empty?
    #     puts "Manifest is valid!"
    #   else
    #     errors.each { |e| puts "Error: #{e}" }
    #   end
    #
    # @example Check validity
    #   Validator.valid?(manifest) # => true/false
    #
    # @example Validate and raise
    #   Validator.validate!(manifest) # raises ValidationError if invalid
    #
    class Validator
      # Known model providers for validation
      KNOWN_PROVIDERS = %w[anthropic openai google meta cohere mistral].freeze

      # Reserved names that cannot be used
      RESERVED_NAMES = %w[agent manifest config settings default system].freeze

      class << self
        # Validate a manifest and return array of error messages
        #
        # @param manifest [Manifest] Manifest to validate
        # @param strict [Boolean] Enable strict validation
        # @return [Array<String>] Error messages (empty if valid)
        def validate(manifest, strict: false)
          errors = []

          errors.concat(validate_meta(manifest))
          errors.concat(validate_model(manifest))
          errors.concat(validate_tools(manifest))
          errors.concat(validate_resources(manifest))
          errors.concat(validate_schemas(manifest))
          errors.concat(validate_extensions(manifest))
          errors.concat(validate_content(manifest))

          errors.concat(validate_strict(manifest)) if strict

          errors
        end

        # Check if a manifest is valid
        #
        # @param manifest [Manifest] Manifest to validate
        # @param strict [Boolean] Enable strict validation
        # @return [Boolean]
        def valid?(manifest, strict: false)
          validate(manifest, strict: strict).empty?
        end

        # Validate and raise if invalid
        #
        # @param manifest [Manifest] Manifest to validate
        # @param strict [Boolean] Enable strict validation
        # @raise [ValidationError] if manifest is invalid
        # @return [Manifest] The validated manifest
        def validate!(manifest, strict: false)
          errors = validate(manifest, strict: strict)
          raise ValidationError, "Invalid manifest: #{errors.join('; ')}" if errors.any?

          manifest
        end

        private

        # Validate meta fields
        def validate_meta(manifest)
          errors = []

          # Name is required
          if manifest.name.blank?
            errors << "name is required"
          else
            # Name format
            unless manifest.name =~ /\A[a-z][a-z0-9\-]*\z/
              errors << "name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens"
            end

            # Name length
            if manifest.name.length > 100
              errors << "name must be 100 characters or less"
            end

            # Reserved names
            if RESERVED_NAMES.include?(manifest.name)
              errors << "name '#{manifest.name}' is reserved"
            end
          end

          # Version format
          if manifest.version.present?
            unless manifest.version =~ /\A\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?\z/
              errors << "version must follow semantic versioning (e.g., 1.0.0, 1.0.0-beta.1)"
            end
          end

          # Tags
          if manifest.tags.is_a?(Array)
            manifest.tags.each do |tag|
              unless tag =~ /\A[a-z][a-z0-9\-]*\z/
                errors << "tag '#{tag}' must be lowercase with hyphens only"
              end
            end
          end

          # Repository URL
          if manifest.repository.present?
            unless manifest.repository =~ %r{\Ahttps?://}
              errors << "repository must be a valid URL"
            end
          end

          errors
        end

        # Validate model configuration
        def validate_model(manifest)
          errors = []

          return errors if manifest.model.blank?

          # Model format - should be provider/model
          if manifest.model.include?("/")
            provider, model_name = manifest.model.split("/", 2)

            # Warn about unknown providers (not an error)
            unless KNOWN_PROVIDERS.include?(provider)
              # This is just informational, not an error
            end

            if model_name.blank?
              errors << "model identifier must include model name after provider"
            end
          end

          # Config validation
          if manifest.config.present?
            # Temperature range
            temp = manifest.config[:temperature] || manifest.config["temperature"]
            if temp && (temp.to_f < 0 || temp.to_f > 2)
              errors << "temperature must be between 0 and 2"
            end

            # Max tokens
            max_tokens = manifest.config[:max_tokens] || manifest.config["max_tokens"]
            if max_tokens && max_tokens.to_i <= 0
              errors << "max_tokens must be a positive integer"
            end

            # Top P
            top_p = manifest.config[:top_p] || manifest.config["top_p"]
            if top_p && (top_p.to_f < 0 || top_p.to_f > 1)
              errors << "top_p must be between 0 and 1"
            end
          end

          errors
        end

        # Validate tool definitions
        def validate_tools(manifest)
          errors = []

          return errors unless manifest.tools.is_a?(Array)

          tool_names = Set.new

          manifest.tools.each_with_index do |tool, index|
            prefix = "tools[#{index}]"

            if tool.reference?
              # Reference validation
              if tool.ref.blank?
                errors << "#{prefix}: $ref cannot be blank"
              end
            else
              # Inline tool validation
              if tool.name.blank?
                errors << "#{prefix}: name is required for inline tools"
              else
                # Check for duplicates
                if tool_names.include?(tool.name)
                  errors << "#{prefix}: duplicate tool name '#{tool.name}'"
                end
                tool_names.add(tool.name)

                # Name format
                unless tool.name =~ /\A[a-zA-Z][a-zA-Z0-9_]*\z/
                  errors << "#{prefix}: name '#{tool.name}' must start with letter and contain only alphanumeric and underscore"
                end
              end

              # Input schema validation
              if tool.input_schema.present?
                unless tool.input_schema.is_a?(Hash)
                  errors << "#{prefix}: inputSchema must be an object"
                else
                  unless tool.input_schema["type"] == "object"
                    errors << "#{prefix}: inputSchema type should be 'object'"
                  end
                end
              end
            end
          end

          errors
        end

        # Validate resource definitions
        def validate_resources(manifest)
          errors = []

          return errors unless manifest.resources.is_a?(Array)

          manifest.resources.each_with_index do |resource, index|
            prefix = "resources[#{index}]"

            if resource.uri.blank?
              errors << "#{prefix}: uri is required"
            else
              # Basic URI format check
              unless resource.uri =~ %r{\A[a-z][a-z0-9+.-]*://}i
                errors << "#{prefix}: uri must be a valid URI with scheme"
              end
            end

            # MIME type format
            if resource.mime_type.present?
              unless resource.mime_type =~ %r{\A[a-z]+/[a-z0-9.+-]+\z}i
                errors << "#{prefix}: mimeType format is invalid"
              end
            end
          end

          errors
        end

        # Validate schemas
        def validate_schemas(manifest)
          errors = []

          # Input schema
          if manifest.input_schema.present?
            begin
              manifest.input_schema.to_json_schema
            rescue StandardError => e
              errors << "input schema is invalid: #{e.message}"
            end
          end

          # Output schema
          if manifest.output_schema.present?
            unless manifest.output_schema.is_a?(Hash)
              errors << "output schema must be an object"
            end
          end

          errors
        end

        # Validate framework extensions
        def validate_extensions(manifest)
          errors = []

          return errors unless manifest.extensions.is_a?(Hash)

          # ActiveAgent extensions
          aa_ext = manifest.extensions[:activeagent]
          if aa_ext.is_a?(Hash)
            # Class name format
            if aa_ext[:class_name].present?
              unless aa_ext[:class_name] =~ /\A[A-Z][a-zA-Z0-9]*Agent\z/
                errors << "activeagent.class_name should follow Rails naming convention (e.g., MyAgent)"
              end
            end

            # Concerns validation
            if aa_ext[:concerns].is_a?(Array)
              aa_ext[:concerns].each do |concern|
                concern_name = concern.is_a?(Hash) ? concern.keys.first : concern
                unless concern_name.to_s =~ /\Ahas_[a-z_]+\z/
                  errors << "activeagent.concerns: '#{concern_name}' should follow has_* naming pattern"
                end
              end
            end
          end

          errors
        end

        # Validate content (instructions, template)
        def validate_content(manifest)
          errors = []

          # Must have some form of content
          if manifest.instructions.blank? && manifest.template.blank?
            errors << "manifest must have instructions or template content"
          end

          # Template syntax check (basic Liquid validation)
          if manifest.template.present?
            # Check for unclosed tags
            open_tags = manifest.template.scan(/\{%\s*(\w+)/).flatten
            close_tags = manifest.template.scan(/\{%\s*end(\w+)/).flatten

            # Simple balance check for common tags
            %w[if for unless case].each do |tag|
              opens = open_tags.count(tag)
              closes = close_tags.count(tag)
              if opens != closes
                errors << "template has unbalanced {% #{tag} %} tags (#{opens} opens, #{closes} closes)"
              end
            end

            # Check for unclosed variable tags
            if manifest.template.count("{{") != manifest.template.count("}}")
              errors << "template has unclosed {{ }} variable tags"
            end
          end

          errors
        end

        # Strict validation (additional checks)
        def validate_strict(manifest)
          errors = []

          # Description required in strict mode
          if manifest.description.blank?
            errors << "description is required in strict mode"
          end

          # Model required in strict mode
          if manifest.model.blank?
            errors << "model is required in strict mode"
          end

          # All tools must have descriptions
          manifest.tools&.each_with_index do |tool, index|
            next if tool.reference?

            if tool.description.blank?
              errors << "tools[#{index}]: description is required in strict mode"
            end
          end

          # Version required in strict mode
          if manifest.version.blank?
            errors << "version is required in strict mode"
          end

          errors
        end
      end
    end
  end
end

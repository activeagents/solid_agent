# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Exporters
      # DotpromptExporter converts Manifests to Google Genkit's .prompt format.
      #
      # @see https://github.com/google/dotprompt
      #
      # @example Export a manifest
      #   content = DotpromptExporter.export(manifest)
      #
      class DotpromptExporter < BaseExporter
        class << self
          def format_name
            :dotprompt
          end

          # Export manifest to .prompt format
          #
          # @param manifest [Manifest] The manifest to export
          # @param use_picoschema [Boolean] Export input schema as Picoschema
          # @return [String] Exported content
          def export(manifest, use_picoschema: true, **)
            frontmatter = build_dotprompt_frontmatter(manifest, use_picoschema)
            body = manifest.template || manifest.instructions || ""

            "#{frontmatter}\n#{body.strip}\n"
          end

          private

          def build_dotprompt_frontmatter(manifest, use_picoschema)
            data = {}

            # Basic fields
            data["name"] = manifest.name if manifest.name.present?
            data["model"] = manifest.model
            data["description"] = manifest.description

            # Config fields - Dotprompt uses camelCase
            if manifest.config&.any?
              data["temperature"] = manifest.config[:temperature] || manifest.config["temperature"]
              data["maxOutputTokens"] = manifest.config[:max_tokens] || manifest.config["max_tokens"]
              data["topP"] = manifest.config[:top_p] || manifest.config["top_p"]
              data["topK"] = manifest.config[:top_k] || manifest.config["top_k"]
              data["stopSequences"] = manifest.config[:stop] || manifest.config["stop"]
            end

            # Input schema
            if manifest.input_schema
              input_data = {}
              if use_picoschema
                input_data["schema"] = manifest.input_schema.to_picoschema
              else
                input_data["schema"] = manifest.input_schema.to_json_schema
              end
              data["input"] = input_data
            end

            # Output schema
            if manifest.output_schema
              data["output"] = manifest.output_schema
            end

            # Tools - Dotprompt format
            if manifest.tools&.any?
              data["tools"] = manifest.tools.map do |tool|
                if tool.reference?
                  tool.ref
                else
                  tool.name
                end
              end
            end

            # Preserve dotprompt-specific extensions
            dotprompt_ext = manifest.extensions&.dig(:dotprompt) || {}
            %w[candidates cache default variant metadata].each do |key|
              data[key] = dotprompt_ext[key] if dotprompt_ext[key].present?
            end

            build_frontmatter(data)
          end
        end
      end

      # Register the exporter
      ExporterRegistry.register(:dotprompt, DotpromptExporter)
    end
  end
end

# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Exporters
      # AgentMdExporter converts Manifests to the native .agent.md format.
      #
      # @example Export a manifest
      #   content = AgentMdExporter.export(manifest)
      #
      # @example Export with options
      #   content = AgentMdExporter.export(manifest, include_examples: true)
      #
      class AgentMdExporter < BaseExporter
        class << self
          def format_name
            :agent_md
          end

          # Export manifest to .agent.md format
          #
          # @param manifest [Manifest] The manifest to export
          # @param include_examples [Boolean] Include examples section
          # @param include_tests [Boolean] Include tests section
          # @return [String] Exported content
          def export(manifest, include_examples: false, include_tests: false, **)
            frontmatter = build_agent_md_frontmatter(manifest, include_examples, include_tests)
            body = build_body(manifest)

            "#{frontmatter}\n#{body}"
          end

          private

          def build_agent_md_frontmatter(manifest, include_examples, include_tests)
            data = {}

            # Meta
            data["name"] = manifest.name
            data["version"] = manifest.version if manifest.version && manifest.version != "1.0.0"
            data["description"] = manifest.description
            data["author"] = manifest.author
            data["license"] = manifest.license
            data["repository"] = manifest.repository
            data["tags"] = manifest.tags if manifest.tags&.any?
            data["extends"] = manifest.extends

            # Model
            data["model"] = manifest.model
            data["config"] = manifest.config if manifest.config&.any?

            # Schemas
            data["input"] = export_input_schema(manifest.input_schema)
            data["output"] = manifest.output_schema

            # Tools & Resources
            data["tools"] = export_tools(manifest.tools)
            data["resources"] = export_resources(manifest.resources)

            # Extensions (preserve framework-specific config)
            manifest.extensions&.each do |framework, config|
              data[framework.to_s] = config if config&.any?
            end

            # Examples & Tests
            data["examples"] = manifest.examples if include_examples && manifest.examples&.any?
            data["tests"] = manifest.tests if include_tests && manifest.tests&.any?

            build_frontmatter(data)
          end

          def build_body(manifest)
            parts = []

            # Title from name
            title = manifest.name.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
            parts << "# #{title}\n"

            # Description
            if manifest.description.present?
              parts << manifest.description
              parts << ""
            end

            # Instructions section
            if manifest.instructions.present? && manifest.instructions != manifest.template
              parts << "## Instructions\n"
              parts << manifest.instructions
              parts << ""
            end

            # Template (if different from instructions or if instructions is nil)
            if manifest.template.present?
              # Check if template is just the full body or needs a section
              if manifest.instructions.blank?
                # Template is the main content
                parts << manifest.template
              elsif manifest.template != manifest.instructions
                parts << "## Template\n"
                parts << "```liquid"
                parts << manifest.template
                parts << "```"
              end
            end

            parts.join("\n").strip + "\n"
          end
        end
      end

      # Register the exporter
      ExporterRegistry.register(:agent_md, AgentMdExporter)
    end
  end
end

# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Exporters
      # CrewAIExporter converts Manifests to CrewAI's agents.yaml format.
      #
      # @see https://docs.crewai.com
      #
      # @example Export a single manifest
      #   content = CrewAIExporter.export(manifest)
      #
      # @example Export multiple manifests
      #   content = CrewAIExporter.export_multiple([manifest1, manifest2])
      #
      class CrewAIExporter < BaseExporter
        class << self
          def format_name
            :crewai
          end

          # Export manifest to CrewAI agents.yaml format
          #
          # @param manifest [Manifest] The manifest to export
          # @return [String] Exported YAML content
          def export(manifest, **)
            export_multiple([manifest])
          end

          # Export multiple manifests to a single agents.yaml
          #
          # @param manifests [Array<Manifest>] Manifests to export
          # @return [String] Exported YAML content
          def export_multiple(manifests)
            agents = {}

            manifests.each do |manifest|
              agent_key = manifest.name.to_s.tr("-", "_")
              agents[agent_key] = build_crewai_agent(manifest)
            end

            # Use YAML dump with custom options for better formatting
            yaml = agents.to_yaml
            # Remove leading ---
            yaml.sub(/\A---\n/, "")
          end

          private

          def build_crewai_agent(manifest)
            agent = {}

            # Extract from CrewAI extensions if present
            crewai_ext = manifest.extensions&.dig(:crewai) || {}

            # Role - from extension or generate from name
            agent["role"] = crewai_ext[:role] || crewai_ext["role"] ||
              manifest.name.to_s.tr("-", " ").split.map(&:capitalize).join(" ")

            # Goal - from extension or description
            agent["goal"] = crewai_ext[:goal] || crewai_ext["goal"] || manifest.description

            # Backstory - from extension or instructions
            backstory = crewai_ext[:backstory] || crewai_ext["backstory"]
            if backstory.blank? && manifest.instructions.present?
              # Extract backstory from instructions if it follows the Role/Goal/Backstory format
              backstory = extract_backstory(manifest.instructions)
            end
            agent["backstory"] = backstory if backstory.present?

            # LLM - strip provider prefix for CrewAI
            agent["llm"] = strip_provider(manifest.model) if manifest.model.present?

            # Tools - CrewAI uses Python class names
            if manifest.tools&.any?
              agent["tools"] = manifest.tools.map do |tool|
                if tool.reference?
                  # Extract tool name from reference
                  tool.ref.to_s.split("://").last.split("/").last
                else
                  # Convert to PascalCase tool class name
                  tool.name.to_s.split(/[-_]/).map(&:capitalize).join + "Tool"
                end
              end
            end

            # CrewAI-specific options from extensions
            %w[verbose allow_delegation max_iter max_rpm memory cache].each do |key|
              value = crewai_ext[key.to_sym] || crewai_ext[key]
              agent[key] = value unless value.nil?
            end

            # Config options
            if manifest.config&.any?
              agent["temperature"] = manifest.config[:temperature] || manifest.config["temperature"]
              agent["max_tokens"] = manifest.config[:max_tokens] || manifest.config["max_tokens"]
            end

            agent.compact
          end

          # Extract backstory from instructions that follow Role/Goal/Backstory format
          def extract_backstory(instructions)
            return nil unless instructions

            # Look for content after "Backstory:" or similar patterns
            if instructions =~ /backstory:?\s*(.+?)(?:\n\n|\z)/mi
              return ::Regexp.last_match(1).strip
            end

            # If instructions don't have Role/Goal prefix, use the whole thing as backstory
            unless instructions =~ /\A\s*(Role:|Goal:)/i
              return instructions
            end

            nil
          end
        end
      end

      # Register the exporter
      ExporterRegistry.register(:crewai, CrewAIExporter)
    end
  end
end

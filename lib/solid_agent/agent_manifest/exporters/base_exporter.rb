# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Exporters
      # BaseExporter provides common functionality for all format exporters.
      #
      # Subclasses should implement:
      # - .export(manifest, **options) - Convert manifest to string
      # - .format_name - Return the format identifier symbol
      #
      class BaseExporter
        class << self
          # Export a manifest to string format
          #
          # @param manifest [Manifest] The manifest to export
          # @param options [Hash] Format-specific options
          # @return [String] Exported content
          def export(manifest, **options)
            raise NotImplementedError, "#{self}.export must be implemented by subclass"
          end

          # Get the format name for this exporter
          #
          # @return [Symbol]
          def format_name
            raise NotImplementedError, "#{self}.format_name must be implemented by subclass"
          end

          protected

          # Build YAML frontmatter from a hash
          #
          # @param data [Hash] Frontmatter data
          # @return [String] YAML frontmatter block
          def build_frontmatter(data)
            # Remove nil values and empty hashes/arrays
            clean_data = deep_compact(data)
            return "" if clean_data.empty?

            yaml_content = clean_data.to_yaml
            # Remove the leading "---\n" that to_yaml adds
            yaml_content = yaml_content.sub(/\A---\n/, "")

            "---\n#{yaml_content}---\n"
          end

          # Deep compact - remove nil values and empty collections recursively
          #
          # @param obj [Object] Object to compact
          # @return [Object] Compacted object
          def deep_compact(obj)
            case obj
            when Hash
              result = {}
              obj.each do |k, v|
                compacted = deep_compact(v)
                result[k] = compacted unless empty_value?(compacted)
              end
              result
            when Array
              obj.map { |v| deep_compact(v) }.reject { |v| empty_value?(v) }
            else
              obj
            end
          end

          # Check if a value should be considered empty
          #
          # @param value [Object]
          # @return [Boolean]
          def empty_value?(value)
            case value
            when nil then true
            when Hash then value.empty?
            when Array then value.empty?
            when String then value.empty?
            else false
            end
          end

          # Convert tools to exportable format
          #
          # @param tools [Array<Tool>] Tools to convert
          # @return [Array<Hash>] Exportable tool data
          def export_tools(tools)
            return nil if tools.nil? || tools.empty?

            tools.map do |tool|
              if tool.reference?
                { "$ref" => tool.ref }
              else
                {
                  "name" => tool.name,
                  "description" => tool.description,
                  "inputSchema" => tool.input_schema
                }.compact
              end
            end
          end

          # Convert resources to exportable format
          #
          # @param resources [Array<Resource>] Resources to convert
          # @return [Array<Hash>] Exportable resource data
          def export_resources(resources)
            return nil if resources.nil? || resources.empty?

            resources.map do |resource|
              {
                "name" => resource.name,
                "description" => resource.description,
                "uri" => resource.uri,
                "mimeType" => resource.mime_type
              }.compact
            end
          end

          # Convert input schema to exportable format
          #
          # @param schema [InputSchema, nil] Schema to convert
          # @return [Hash, nil] Exportable schema data
          def export_input_schema(schema)
            return nil unless schema

            { "schema" => schema.schema }
          end

          # Strip provider prefix from model identifier
          #
          # @param model [String, nil] Full model identifier
          # @return [String, nil] Model name without provider
          def strip_provider(model)
            return nil unless model
            model.to_s.split("/").last
          end

          # Wrap text at specified width
          #
          # @param text [String] Text to wrap
          # @param width [Integer] Maximum line width
          # @return [String] Wrapped text
          def word_wrap(text, width: 80)
            return text unless text

            text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
          end
        end
      end
    end
  end
end

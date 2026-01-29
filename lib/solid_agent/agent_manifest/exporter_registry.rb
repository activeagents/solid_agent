# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # ExporterRegistry manages format exporters for converting Manifests to various formats.
    #
    # @example Register an exporter
    #   ExporterRegistry.register(:agent_md, AgentMdExporter)
    #
    # @example Export a manifest
    #   content = ExporterRegistry.export(manifest, :dotprompt)
    #
    # @example Export to file
    #   ExporterRegistry.export_to_file(manifest, :agent_md, "agent.agent.md")
    #
    class ExporterRegistry
      class << self
        # Registered exporters by format name
        #
        # @return [Hash<Symbol, Class>]
        def exporters
          @exporters ||= {}
        end

        # Register an exporter for a format
        #
        # @param format [Symbol] Format name
        # @param exporter_class [Class] Exporter class
        def register(format, exporter_class)
          exporters[format.to_sym] = exporter_class
        end

        # Get the exporter for a format
        #
        # @param format [Symbol, String] Format name
        # @return [Class] Exporter class
        # @raise [UnknownFormatError] if format not recognized
        def exporter_for(format)
          format_sym = format.to_sym
          exporters[format_sym] || raise(UnknownFormatError, "Unknown export format: #{format}")
        end

        # Check if a format is supported
        #
        # @param format [Symbol, String] Format name
        # @return [Boolean]
        def supports?(format)
          exporters.key?(format.to_sym)
        end

        # List all registered format names
        #
        # @return [Array<Symbol>]
        def formats
          exporters.keys
        end

        # Export a manifest to a format string
        #
        # @param manifest [Manifest] The manifest to export
        # @param format [Symbol, String] Target format
        # @param options [Hash] Format-specific options
        # @return [String] Exported content
        def export(manifest, format, **options)
          exporter = exporter_for(format)
          exporter.export(manifest, **options)
        end

        # Export a manifest to a file
        #
        # @param manifest [Manifest] The manifest to export
        # @param format [Symbol, String] Target format
        # @param path [String] Output file path
        # @param options [Hash] Format-specific options
        # @return [String] The path written to
        def export_to_file(manifest, format, path, **options)
          content = export(manifest, format, **options)
          File.write(path, content, encoding: "UTF-8")
          path
        end

        # Convert between formats
        #
        # @param input_path [String] Source file path
        # @param output_format [Symbol, String] Target format
        # @param output_path [String, nil] Output path (auto-generated if nil)
        # @return [String] Output path
        def convert(input_path, output_format, output_path = nil)
          manifest = ParserRegistry.parse(input_path)

          output_path ||= generate_output_path(input_path, output_format)
          export_to_file(manifest, output_format, output_path)
        end

        private

        # Generate output path based on format
        def generate_output_path(input_path, format)
          base = File.basename(input_path, ".*")
          # Remove any existing format extensions
          base = base.sub(/\.(agent|prompt)$/, "")
          dir = File.dirname(input_path)

          extension = case format.to_sym
          when :agent_md then ".agent.md"
          when :dotprompt then ".prompt"
          when :crewai then ".yaml"
          when :github_prompt then ".prompt.md"
          else ".#{format}"
          end

          File.join(dir, "#{base}#{extension}")
        end
      end
    end
  end
end

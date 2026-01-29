# frozen_string_literal: true

require_relative "agent_manifest/errors"
require_relative "agent_manifest/manifest"
require_relative "agent_manifest/tool"
require_relative "agent_manifest/resource"
require_relative "agent_manifest/input_schema"
require_relative "agent_manifest/picoschema"
require_relative "agent_manifest/parser_registry"
require_relative "agent_manifest/parsers/base_parser"
require_relative "agent_manifest/parsers/agent_md_parser"
require_relative "agent_manifest/parsers/dotprompt_parser"
require_relative "agent_manifest/parsers/crewai_parser"
require_relative "agent_manifest/parsers/github_prompt_parser"
require_relative "agent_manifest/exporter_registry"
require_relative "agent_manifest/exporters/base_exporter"
require_relative "agent_manifest/exporters/agent_md_exporter"
require_relative "agent_manifest/exporters/dotprompt_exporter"
require_relative "agent_manifest/exporters/crewai_exporter"
require_relative "agent_manifest/validator"
require_relative "agent_manifest/agent_builder"
require_relative "agent_manifest/registry/auth"
require_relative "agent_manifest/registry/client"

module SolidAgent
  # AgentManifest provides a unified interface for working with agent definition files.
  #
  # Supports multiple formats:
  # - `.agent.md` - Native format with full feature support
  # - `.prompt` - Google Dotprompt format
  # - `agents.yaml` - CrewAI format
  # - `.prompt.md` - GitHub Copilot format
  #
  # @example Parse a manifest file
  #   manifest = SolidAgent::AgentManifest.parse("research_assistant.agent.md")
  #
  # @example Parse with auto-detection
  #   manifest = SolidAgent::AgentManifest.parse("agents.yaml")
  #
  # @example Export to different format
  #   content = SolidAgent::AgentManifest.export(manifest, :dotprompt)
  #
  # @example Convert between formats
  #   SolidAgent::AgentManifest.convert("agent.yaml", :agent_md, "agent.agent.md")
  #
  # @example Load as agent class
  #   klass = SolidAgent::AgentManifest.load_agent("research.agent.md")
  #   agent = klass.new
  #
  # @example Validate a manifest
  #   errors = SolidAgent::AgentManifest.validate("agent.agent.md")
  #
  module AgentManifest
    class << self
      # Parse a manifest file
      #
      # @param path [String] Path to manifest file
      # @param format [Symbol, nil] Force specific format (auto-detected if nil)
      # @return [Manifest] Parsed manifest
      # @raise [ParseError] if parsing fails
      # @raise [UnknownFormatError] if format cannot be determined
      def parse(path, format: nil)
        ParserRegistry.parse(path, format: format)
      end

      # Parse manifest content from a string
      #
      # @param content [String] Manifest content
      # @param format [Symbol] Format of the content
      # @return [Manifest] Parsed manifest
      def parse_string(content, format:)
        ParserRegistry.parse_string(content, format: format)
      end

      # Export a manifest to a format string
      #
      # @param manifest [Manifest] Manifest to export
      # @param format [Symbol] Target format (:agent_md, :dotprompt, :crewai)
      # @param options [Hash] Format-specific options
      # @return [String] Exported content
      def export(manifest, format, **options)
        ExporterRegistry.export(manifest, format, **options)
      end

      # Export a manifest to a file
      #
      # @param manifest [Manifest] Manifest to export
      # @param format [Symbol] Target format
      # @param path [String] Output file path
      # @param options [Hash] Format-specific options
      # @return [String] The path written to
      def export_to_file(manifest, format, path, **options)
        ExporterRegistry.export_to_file(manifest, format, path, **options)
      end

      # Convert a manifest file between formats
      #
      # @param input_path [String] Source file path
      # @param output_format [Symbol] Target format
      # @param output_path [String, nil] Output path (auto-generated if nil)
      # @return [String] Output path
      def convert(input_path, output_format, output_path = nil)
        ExporterRegistry.convert(input_path, output_format, output_path)
      end

      # Load an agent class from a manifest file
      #
      # @param path [String] Path to manifest file
      # @param base_class [Class, nil] Base class to inherit from
      # @param class_name [String, nil] Optional class name for registration
      # @return [Class] The generated agent class
      def load_agent(path, base_class: nil, class_name: nil)
        manifest = parse(path)
        AgentBuilder.build(manifest, base_class: base_class, class_name: class_name)
      end

      # Load and instantiate an agent from a manifest file
      #
      # @param path [String] Path to manifest file
      # @param params [Hash] Parameters to pass to the agent
      # @param options [Hash] Options passed to build
      # @return [Object] The instantiated agent
      def load_agent_instance(path, params: {}, **options)
        manifest = parse(path)
        AgentBuilder.build_instance(manifest, params: params, **options)
      end

      # Validate a manifest file or object
      #
      # @param path_or_manifest [String, Manifest] Path to file or Manifest object
      # @param strict [Boolean] Enable strict validation
      # @return [Array<String>] Array of error messages (empty if valid)
      def validate(path_or_manifest, strict: false)
        manifest = path_or_manifest.is_a?(String) ? parse(path_or_manifest) : path_or_manifest
        Validator.validate(manifest, strict: strict)
      end

      # Check if a manifest is valid
      #
      # @param path_or_manifest [String, Manifest] Path to file or Manifest object
      # @param strict [Boolean] Enable strict validation
      # @return [Boolean]
      def valid?(path_or_manifest, strict: false)
        validate(path_or_manifest, strict: strict).empty?
      end

      # Validate and raise if invalid
      #
      # @param path_or_manifest [String, Manifest] Path to file or Manifest object
      # @param strict [Boolean] Enable strict validation
      # @raise [ValidationError] if invalid
      # @return [Manifest] The validated manifest
      def validate!(path_or_manifest, strict: false)
        manifest = path_or_manifest.is_a?(String) ? parse(path_or_manifest) : path_or_manifest
        Validator.validate!(manifest, strict: strict)
      end

      # List supported parser formats
      #
      # @return [Array<Symbol>]
      def parser_formats
        ParserRegistry.formats
      end

      # List supported exporter formats
      #
      # @return [Array<Symbol>]
      def exporter_formats
        ExporterRegistry.formats
      end

      # Detect the format of a file
      #
      # @param path [String] Path to file
      # @return [Symbol] Detected format
      # @raise [UnknownFormatError] if format cannot be determined
      def detect_format(path)
        ParserRegistry.detect_format(path)
      end
    end
  end
end

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

require "digest"
require "json"

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
  # @example Load from any source
  #   manifest = SolidAgent::AgentManifest.load("https://example.com/agent.md")
  #   manifest = SolidAgent::AgentManifest.load({ name: "quick", model: "gpt-4o" })
  #
  module AgentManifest
    class << self
      # ============================================
      # Unified Loading API
      # ============================================

      # Load manifest from any source with auto-detection
      #
      # @param source [String, Hash] File path, URL, JSON string, YAML string, or Hash
      # @param format [Symbol] Force format (:agent_md, :json, :yaml, :dotprompt, :crewai)
      # @return [Manifest] Parsed manifest
      def load(source, format: nil)
        case source
        when Hash
          from_hash(source)
        when ->(s) { s.is_a?(String) && s.match?(%r{\Ahttps?://}) }
          from_url(source, format: format)
        when ->(s) { s.is_a?(String) && File.exist?(s) }
          from_file(source, format: format)
        when String
          from_string(source, format: format || detect_string_format(source))
        else
          raise ArgumentError, "Unknown source type: #{source.class}"
        end
      end

      # Load manifest from URL
      #
      # @param url [String] URL to fetch manifest from
      # @param format [Symbol] Force format (auto-detected if nil)
      # @return [Manifest] Parsed manifest
      def from_url(url, format: nil)
        require "net/http"
        require "uri"

        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise SolidAgent::LoadError, "Failed to fetch #{url}: #{response.code}"
        end

        format ||= detect_format_from_url(url) || detect_format_from_content_type(response)
        manifest = from_string(response.body, format: format)
        manifest.source_path = url
        manifest
      end

      # Load manifest from file
      #
      # @param path [String] Path to manifest file
      # @param format [Symbol] Force format (auto-detected if nil)
      # @return [Manifest] Parsed manifest
      def from_file(path, format: nil)
        parse(path, format: format)
      end

      # Load manifest from string content
      #
      # @param content [String] Manifest content
      # @param format [Symbol] Content format
      # @return [Manifest] Parsed manifest
      def from_string(content, format:)
        parse_string(content, format: format)
      end

      # Load manifest from JSON string
      #
      # @param json_string [String] JSON content
      # @return [Manifest] Parsed manifest
      def from_json(json_string)
        from_hash(JSON.parse(json_string, symbolize_names: true))
      end

      # Load manifest from YAML string
      #
      # @param yaml_string [String] YAML content
      # @return [Manifest] Parsed manifest
      def from_yaml(yaml_string)
        require "yaml"
        from_hash(YAML.safe_load(yaml_string, symbolize_names: true, permitted_classes: [Symbol]))
      end

      # Load manifest from Hash
      #
      # @param hash [Hash] Manifest attributes
      # @return [Manifest] Parsed manifest
      def from_hash(hash)
        Manifest.new(**hash.transform_keys(&:to_sym))
      end

      # Build agent class from manifest
      #
      # @param manifest [Manifest] Manifest to build from
      # @param base_class [Class] Parent class
      # @param class_name [String] Name to register constant as
      # @return [Class] Generated agent class
      def build(manifest, base_class: nil, class_name: nil)
        AgentBuilder.build(manifest, base_class: base_class, class_name: class_name)
      end

      # Build agent instance from manifest
      #
      # @param manifest [Manifest] Manifest to build from
      # @param params [Hash] Parameters for the agent
      # @return [Object] Agent instance
      def build_instance(manifest, params: {}, **options)
        AgentBuilder.build_instance(manifest, params: params, **options)
      end

      # ============================================
      # Provenance & Checksums
      # ============================================

      # Generate checksum for any content
      #
      # @param content [String, Hash, Object] Content to checksum
      # @return [String] MD5 hex digest
      def checksum(content)
        data = case content
        when String then content
        when Hash then content.to_json
        else content.to_s
        end
        Digest::MD5.hexdigest(data)
      end

      # Generate provenance record for a manifest
      #
      # @param manifest [Manifest] Manifest to generate provenance for
      # @return [Hash] Provenance record with checksums
      def provenance(manifest)
        {
          manifest_checksum: checksum(manifest.to_h),
          instructions_checksum: manifest.instructions ? checksum(manifest.instructions) : nil,
          model: manifest.model,
          version: manifest.version,
          source_path: manifest.source_path,
          source_format: manifest.source_format,
          generated_at: Time.now.iso8601,
          tools: manifest.tools&.map { |t| { name: t.name, checksum: checksum(t.to_h) } }
        }.compact
      end

      # ============================================
      # Original API (maintained for compatibility)
      # ============================================

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

      private

      # Detect format from string content
      def detect_string_format(content)
        content = content.strip
        if content.start_with?("{") || content.start_with?("[")
          :json
        elsif content.start_with?("---")
          # Could be YAML frontmatter (agent.md) or pure YAML
          if content.match?(/\n---\s*\n/)
            :agent_md
          else
            :yaml
          end
        elsif content.match?(/^\w+:\s/)
          :yaml
        elsif content.match?(/^#\s/)
          :agent_md
        else
          :yaml
        end
      end

      # Detect format from URL path
      def detect_format_from_url(url)
        require "uri"
        path = URI.parse(url).path
        case File.extname(path)
        when ".json" then :json
        when ".yaml", ".yml" then :yaml
        when ".md" then :agent_md
        when ".prompt" then :dotprompt
        end
      end

      # Detect format from HTTP content-type
      def detect_format_from_content_type(response)
        content_type = response["content-type"].to_s
        case content_type
        when /json/ then :json
        when /yaml/ then :yaml
        when /markdown/ then :agent_md
        else nil
        end
      end
    end
  end
end

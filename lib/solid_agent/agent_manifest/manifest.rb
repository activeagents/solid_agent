# frozen_string_literal: true

require "digest"

module SolidAgent
  module AgentManifest
    # Manifest represents a unified, portable AI agent definition.
    #
    # It serves as the canonical internal representation that all parsers
    # produce and all exporters consume, enabling cross-framework compatibility.
    #
    # @example Creating a manifest
    #   manifest = Manifest.new(
    #     name: "research-assistant",
    #     model: "anthropic/claude-sonnet-4-20250514",
    #     description: "An agent that researches topics"
    #   )
    #
    # @example Validating a manifest
    #   manifest.valid?  # => true/false
    #   manifest.errors.full_messages  # => ["Name can't be blank"]
    #
    class Manifest
      include ActiveModel::Model
      include ActiveModel::Validations

      # === Meta attributes ===
      # @return [String] Unique identifier (lowercase, hyphens only)
      attr_accessor :name

      # @return [String] SemVer version string (default: "1.0.0")
      attr_accessor :version

      # @return [String, nil] Brief description (max 280 chars)
      attr_accessor :description

      # @return [String, nil] Author name or organization
      attr_accessor :author

      # @return [String, nil] SPDX license identifier
      attr_accessor :license

      # @return [String, nil] Source repository URL
      attr_accessor :repository

      # @return [Array<String>] Categorization tags
      attr_accessor :tags

      # @return [String, nil] Parent agent to inherit from
      attr_accessor :extends

      # === Model configuration ===
      # @return [String, nil] Model identifier (provider/model format)
      attr_accessor :model

      # @return [Hash] Model-specific parameters (temperature, max_tokens, etc.)
      attr_accessor :config

      # === Schemas ===
      # @return [InputSchema, nil] Expected input structure
      attr_accessor :input_schema

      # @return [Hash, nil] Expected output format and structure
      attr_accessor :output_schema

      # === Tools & Resources ===
      # @return [Array<Tool>] Available tools
      attr_accessor :tools

      # @return [Array<Resource>] External data sources
      attr_accessor :resources

      # === Instructions ===
      # @return [String, nil] Extracted instructions from template
      attr_accessor :instructions

      # @return [String, nil] Full template content (with Liquid syntax)
      attr_accessor :template

      # === Framework extensions ===
      # @return [Hash] Framework-specific configuration (activeagent:, crewai:, etc.)
      attr_accessor :extensions

      # === Source tracking ===
      # @return [Symbol, nil] Original format (:agent_md, :dotprompt, etc.)
      attr_accessor :source_format

      # @return [String, nil] Original file path
      attr_accessor :source_path

      # === Examples & Tests ===
      # @return [Array<Hash>] Example inputs/outputs
      attr_accessor :examples

      # @return [Array<Hash>] Test cases
      attr_accessor :tests

      # === Validations ===
      validates :name, presence: true,
                format: {
                  with: /\A[a-z][a-z0-9\-]*\z/,
                  message: "must start with lowercase letter and contain only lowercase letters, numbers, and hyphens"
                },
                allow_blank: false

      validates :version,
                format: {
                  with: /\A\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?\z/,
                  message: "must be valid semver (e.g., 1.0.0, 1.0.0-beta.1)"
                },
                allow_blank: true

      validates :model,
                format: {
                  with: %r{\A[a-z0-9_-]+/[a-z0-9._-]+\z}i,
                  message: "must be in provider/model format (e.g., anthropic/claude-sonnet-4-20250514)"
                },
                allow_blank: true

      validate :validate_tools
      validate :validate_extensions

      def initialize(attributes = {})
        # Set defaults before calling super
        @version = "1.0.0"
        @tags = []
        @tools = []
        @resources = []
        @extensions = {}
        @config = {}
        @examples = []
        @tests = []

        super(attributes)

        # Ensure arrays and hashes are properly initialized even if nil was passed
        @tags ||= []
        @tools ||= []
        @resources ||= []
        @extensions ||= {}
        @config ||= {}
        @examples ||= []
        @tests ||= []
      end

      # === Convenience accessors for framework extensions ===

      # @return [Hash] ActiveAgent-specific configuration
      def activeagent_config
        extensions[:activeagent] || extensions["activeagent"] || {}
      end

      # @return [Hash] CrewAI-specific configuration
      def crewai_config
        extensions[:crewai] || extensions["crewai"] || {}
      end

      # @return [Hash] LangChain-specific configuration
      def langchain_config
        extensions[:langchain] || extensions["langchain"] || {}
      end

      # @return [Hash] Genkit/Dotprompt-specific configuration
      def genkit_config
        extensions[:genkit] || extensions["genkit"] || {}
      end

      # Convert manifest to a hash representation
      #
      # @return [Hash] Hash representation suitable for serialization
      def to_h
        {
          name: name,
          version: version,
          description: description,
          author: author,
          license: license,
          repository: repository,
          tags: tags.presence,
          extends: extends,
          model: model,
          config: config.presence,
          input_schema: input_schema&.to_h,
          output_schema: output_schema,
          tools: tools.map(&:to_h).presence,
          resources: resources.map(&:to_h).presence,
          instructions: instructions,
          template: template,
          extensions: extensions.presence
        }.compact
      end

      # Convert to JSON string
      #
      # @return [String] JSON representation
      def to_json(*args)
        to_h.to_json(*args)
      end

      # Check if this manifest has any tools defined
      #
      # @return [Boolean]
      def has_tools?
        tools.any?
      end

      # Check if this manifest has any resources defined
      #
      # @return [Boolean]
      def has_resources?
        resources.any?
      end

      # Check if this manifest extends another agent
      #
      # @return [Boolean]
      def extends?
        extends.present?
      end

      # Get tool by name
      #
      # @param tool_name [String, Symbol] Name of the tool
      # @return [Tool, nil]
      def tool(tool_name)
        tools.find { |t| t.name.to_s == tool_name.to_s }
      end

      # ============================================
      # Provenance & Checksums
      # ============================================

      # Generate MD5 checksum of manifest content
      #
      # @return [String] 32-character hex digest
      def checksum
        Digest::MD5.hexdigest(to_h.to_json)
      end
      alias_method :digest, :checksum

      # Generate checksum of instructions only
      #
      # @return [String, nil] Hex digest or nil if no instructions
      def instructions_checksum
        return nil unless instructions.present?
        Digest::MD5.hexdigest(instructions)
      end

      # Generate checksum of model configuration
      #
      # @return [String] Hex digest of model + config
      def config_checksum
        Digest::MD5.hexdigest({ model: model, config: config }.to_json)
      end

      # Generate full provenance record
      #
      # @return [Hash] Provenance data for tracing
      def provenance
        {
          manifest_checksum: checksum,
          instructions_checksum: instructions_checksum,
          config_checksum: config_checksum,
          name: name,
          version: version,
          model: model,
          source_path: source_path,
          source_format: source_format,
          generated_at: Time.now.iso8601,
          tools_checksums: tools.map { |t| { name: t.name, checksum: Digest::MD5.hexdigest(t.to_h.to_json) } }
        }.compact
      end

      # Short identifier combining name, version, and checksum prefix
      #
      # @return [String] e.g., "research-agent@1.0.0#a1b2c3d4"
      def fingerprint
        "#{name}@#{version}##{checksum[0..7]}"
      end

      private

      def validate_tools
        tools.each_with_index do |tool, index|
          next if tool.is_a?(Tool)

          errors.add(:tools, "item at index #{index} must be a Tool instance")
        end
      end

      def validate_extensions
        return unless extensions.present?

        unless extensions.is_a?(Hash)
          errors.add(:extensions, "must be a hash")
          return
        end

        # Validate known extension structures
        if activeagent_config.present? && !activeagent_config.is_a?(Hash)
          errors.add(:extensions, "activeagent config must be a hash")
        end
      end
    end
  end
end

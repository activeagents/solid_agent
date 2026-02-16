# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # Resource represents an external data source that an agent can access.
    #
    # Resources follow MCP (Model Context Protocol) conventions and can represent
    # files, APIs, databases, or other data sources.
    #
    # @example File resource
    #   resource = Resource.new(
    #     name: "company_docs",
    #     description: "Internal company documentation",
    #     uri: "file:///docs/**/*.md",
    #     mime_type: "text/markdown"
    #   )
    #
    # @example API resource
    #   resource = Resource.new(
    #     name: "api_spec",
    #     description: "OpenAPI specification",
    #     uri: "https://api.example.com/openapi.json",
    #     mime_type: "application/json"
    #   )
    #
    class Resource
      # @return [String] Resource identifier
      attr_accessor :name

      # @return [String, nil] Human-readable description
      attr_accessor :description

      # @return [String] URI pattern or URL
      attr_accessor :uri

      # @return [String, nil] MIME type of the resource content
      attr_accessor :mime_type

      def initialize(attributes = {})
        attributes.each do |key, value|
          setter = "#{key}="
          send(setter, value) if respond_to?(setter)
        end
      end

      # Convert to hash representation
      #
      # @return [Hash]
      def to_h
        {
          name: name,
          description: description,
          uri: uri,
          mimeType: mime_type
        }.compact
      end

      # Create from hash (flexible key formats)
      #
      # @param data [Hash]
      # @return [Resource]
      def self.from_hash(data)
        new(
          name: data["name"] || data[:name],
          description: data["description"] || data[:description],
          uri: data["uri"] || data[:uri],
          mime_type: data["mimeType"] || data["mime_type"] || data[:mime_type] || data[:mimeType]
        )
      end

      # Check if this is a file resource
      #
      # @return [Boolean]
      def file?
        uri&.start_with?("file://")
      end

      # Check if this is an HTTP resource
      #
      # @return [Boolean]
      def http?
        uri&.match?(%r{\Ahttps?://})
      end

      # Check if resource is valid
      #
      # @return [Boolean]
      def valid?
        name.present? && uri.present?
      end

      # Validation errors
      #
      # @return [Array<String>]
      def validation_errors
        errors = []
        errors << "Resource must have a name" if name.blank?
        errors << "Resource must have a uri" if uri.blank?
        errors
      end
    end
  end
end

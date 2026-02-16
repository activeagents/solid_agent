# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # Tool represents a function/tool that an agent can invoke.
    #
    # Tools follow the MCP (Model Context Protocol) conventions for maximum
    # portability across different LLM providers and frameworks.
    #
    # @example Inline tool definition
    #   tool = Tool.new(
    #     name: "search",
    #     description: "Search the web for information",
    #     input_schema: {
    #       "type" => "object",
    #       "properties" => {
    #         "query" => { "type" => "string", "description" => "Search query" }
    #       },
    #       "required" => ["query"]
    #     }
    #   )
    #
    # @example Tool reference
    #   tool = Tool.new(ref: "@activeagents/web-tools/search")
    #
    class Tool
      # @return [String, nil] Tool name (required for inline definitions)
      attr_accessor :name

      # @return [String, nil] Human-readable description
      attr_accessor :description

      # @return [Hash, nil] JSON Schema for tool input parameters
      attr_accessor :input_schema

      # @return [String, nil] Reference to external tool (e.g., "$ref" or package reference)
      attr_accessor :ref

      def initialize(attributes = {})
        attributes.each do |key, value|
          setter = "#{key}="
          send(setter, value) if respond_to?(setter)
        end
      end

      # Check if this tool is a reference to an external tool
      #
      # @return [Boolean]
      def reference?
        ref.present?
      end

      # Check if this tool has an inline definition
      #
      # @return [Boolean]
      def inline?
        !reference? && name.present?
      end

      # Convert to hash representation
      #
      # @return [Hash]
      def to_h
        if reference?
          { "$ref" => ref }
        else
          {
            name: name,
            description: description,
            inputSchema: input_schema
          }.compact
        end
      end

      # Convert to MCP-compatible JSON string
      #
      # @return [String] JSON representation following MCP tool format
      def to_mcp_json
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }.compact.to_json
      end

      # Convert to HasTools::ToolBuilder compatible schema
      #
      # This format is compatible with OpenAI's function calling API
      # and SolidAgent's existing HasTools concern.
      #
      # @return [Hash]
      def to_tool_builder_schema
        {
          type: "function",
          name: name,
          description: description,
          parameters: input_schema || { type: "object", properties: {} }
        }
      end

      # Create a Tool from a HasTools::ToolBuilder schema
      #
      # @param schema [Hash] Schema from ToolBuilder
      # @return [Tool]
      def self.from_tool_builder(schema)
        new(
          name: schema[:name] || schema["name"],
          description: schema[:description] || schema["description"],
          input_schema: schema[:parameters] || schema["parameters"]
        )
      end

      # Create a Tool from a hash (flexible key formats)
      #
      # @param data [Hash] Tool data with various key formats
      # @return [Tool]
      def self.from_hash(data)
        return new(ref: data["$ref"]) if data["$ref"]

        new(
          name: data["name"] || data[:name],
          description: data["description"] || data[:description],
          input_schema: data["inputSchema"] || data["input_schema"] || data[:input_schema] || data[:inputSchema]
        )
      end

      # Get list of required parameters
      #
      # @return [Array<String>]
      def required_parameters
        input_schema&.dig("required") || input_schema&.dig(:required) || []
      end

      # Get all parameter names
      #
      # @return [Array<String>]
      def parameter_names
        properties = input_schema&.dig("properties") || input_schema&.dig(:properties) || {}
        properties.keys.map(&:to_s)
      end

      # Check if tool is valid (has required fields)
      #
      # @return [Boolean]
      def valid?
        reference? || name.present?
      end

      # Validation errors
      #
      # @return [Array<String>]
      def validation_errors
        errors = []
        errors << "Tool must have a name or $ref" unless valid?
        errors << "Tool description is recommended" if inline? && description.blank?
        errors
      end
    end
  end
end

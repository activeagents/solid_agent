# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # InputSchema wraps a schema definition, supporting both Picoschema
    # (compact YAML format) and JSON Schema formats.
    #
    # Provides bidirectional conversion between formats for interoperability.
    #
    # @example Picoschema format
    #   schema = InputSchema.new(
    #     schema: {
    #       "query" => "string, the search query",
    #       "limit?" => "integer, max results"
    #     },
    #     format: :picoschema
    #   )
    #   schema.to_json_schema  # => JSON Schema object
    #
    # @example JSON Schema format
    #   schema = InputSchema.new(
    #     schema: {
    #       "type" => "object",
    #       "properties" => { "query" => { "type" => "string" } }
    #     },
    #     format: :json_schema
    #   )
    #   schema.to_picoschema  # => Picoschema object
    #
    class InputSchema
      # @return [Hash] The schema definition
      attr_accessor :schema

      # @return [Symbol] Schema format (:picoschema or :json_schema)
      attr_accessor :format

      def initialize(schema:, format: :picoschema)
        @schema = schema
        @format = format.to_sym
      end

      # Convert schema to JSON Schema format
      #
      # @return [Hash] JSON Schema object
      def to_json_schema
        case format
        when :picoschema
          Picoschema.to_json_schema(schema)
        when :json_schema
          schema
        else
          raise SchemaError, "Unknown schema format: #{format}"
        end
      end

      # Convert schema to Picoschema format
      #
      # @return [Hash] Picoschema object
      def to_picoschema
        case format
        when :picoschema
          schema
        when :json_schema
          Picoschema.from_json_schema(schema)
        else
          raise SchemaError, "Unknown schema format: #{format}"
        end
      end

      # Convert to hash representation
      #
      # @return [Hash]
      def to_h
        {
          schema: schema,
          format: format
        }
      end

      # Validate input data against this schema
      #
      # Requires the json_schemer gem for validation.
      #
      # @param input_hash [Hash] Input data to validate
      # @return [Array<String>] List of validation errors (empty if valid)
      def validate_input(input_hash)
        return [] unless defined?(JSONSchemer)

        json_schema = to_json_schema
        schemer = JSONSchemer.schema(json_schema)
        schemer.validate(input_hash).map { |error| error["error"] }
      rescue => e
        ["Schema validation error: #{e.message}"]
      end

      # Check if input is valid against schema
      #
      # @param input_hash [Hash] Input data to validate
      # @return [Boolean]
      def valid_input?(input_hash)
        validate_input(input_hash).empty?
      end

      # Get list of required field names
      #
      # @return [Array<String>]
      def required_fields
        json = to_json_schema
        json["required"] || []
      end

      # Get all field names
      #
      # @return [Array<String>]
      def field_names
        json = to_json_schema
        (json["properties"] || {}).keys
      end

      # Get field definition
      #
      # @param field_name [String] Name of the field
      # @return [Hash, nil] Field schema definition
      def field(field_name)
        json = to_json_schema
        json.dig("properties", field_name.to_s)
      end

      # Create from various input formats
      #
      # @param data [Hash] Schema data
      # @return [InputSchema]
      def self.from_hash(data)
        schema = data["schema"] || data[:schema]
        format = data["format"] || data[:format] || detect_format(schema)

        new(schema: schema, format: format)
      end

      # Detect schema format from content
      #
      # @param schema [Hash] Schema to analyze
      # @return [Symbol] Detected format
      def self.detect_format(schema)
        return :json_schema if schema.nil?
        return :json_schema if schema["type"].present?
        return :json_schema if schema["properties"].present?
        return :json_schema if schema["$schema"].present?

        :picoschema
      end
    end
  end
end

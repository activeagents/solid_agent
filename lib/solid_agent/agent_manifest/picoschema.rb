# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # Picoschema provides bidirectional conversion between Picoschema
    # (a compact, YAML-optimized schema format from Dotprompt) and JSON Schema.
    #
    # Picoschema is designed for human readability while JSON Schema provides
    # full validation capabilities.
    #
    # @example Picoschema syntax
    #   # Simple types
    #   query: string, the search query
    #   limit?: integer                    # optional field
    #
    #   # Enums
    #   status: string(draft, published, archived)
    #
    #   # Arrays
    #   tags: [string]
    #
    #   # Nested objects
    #   author: object
    #     name: string
    #     email: string
    #
    #   # Array of objects
    #   comments: [object]
    #     author: string
    #     text: string
    #
    class Picoschema
      SCALAR_TYPES = %w[string integer number boolean any].freeze

      class << self
        # Convert Picoschema to JSON Schema
        #
        # @param picoschema [Hash] Picoschema definition
        # @return [Hash] JSON Schema object
        def to_json_schema(picoschema)
          return { "type" => "object", "properties" => {} } if picoschema.nil?
          return picoschema if json_schema?(picoschema)

          parse_object(picoschema)
        end

        # Convert JSON Schema to Picoschema
        #
        # @param json_schema [Hash] JSON Schema object
        # @return [Hash] Picoschema definition
        def from_json_schema(json_schema)
          return {} if json_schema.nil?
          return json_schema unless json_schema?(json_schema)

          properties = json_schema["properties"] || json_schema[:properties] || {}
          required = json_schema["required"] || json_schema[:required] || []

          convert_properties(properties, required)
        end

        # Parse a single type string (e.g., "string, description")
        #
        # @param type_str [String] Type definition string
        # @return [Hash] JSON Schema for the field
        def parse_type_string(type_str)
          return { "type" => "any" } if type_str.nil? || type_str.strip == "any"

          str = type_str.to_s.strip

          # Handle enum types first: string(a, b, c), description
          # Need to split after the closing paren for enum types
          if str =~ /\A(\w+\([^)]+\))(,\s*(.+))?\z/
            type_part = ::Regexp.last_match(1).strip
            description = ::Regexp.last_match(3)&.strip
          else
            # Normal split for non-enum types
            parts = str.split(",", 2)
            type_part = parts[0].strip
            description = parts[1]&.strip
          end

          result = parse_type_part(type_part)
          result["description"] = description if description.present?
          result
        end

        private

        # Check if a hash looks like JSON Schema
        def json_schema?(schema)
          return false unless schema.is_a?(Hash)

          schema.key?("type") || schema.key?(:type) ||
            schema.key?("properties") || schema.key?(:properties) ||
            schema.key?("$schema") || schema.key?(:"$schema")
        end

        # Parse an object schema (hash of field definitions)
        def parse_object(schema_hash)
          properties = {}
          required = []

          schema_hash.each do |key, value|
            field_name, optional = parse_field_name(key.to_s)
            field_schema = parse_field_value(value)

            properties[field_name] = field_schema
            required << field_name unless optional
          end

          result = { "type" => "object", "properties" => properties }
          result["required"] = required if required.any?
          result
        end

        # Parse field name, detecting optional marker
        def parse_field_name(key)
          if key.end_with?("?")
            [key.chomp("?"), true]  # optional
          else
            [key, false]  # required
          end
        end

        # Parse a field value (could be type string, hash, or array)
        def parse_field_value(value)
          case value
          when String
            parse_type_string(value)
          when Hash
            # Nested object or already parsed schema
            if json_schema?(value)
              value
            else
              parse_object(value)
            end
          when Array
            parse_array_type(value)
          else
            { "type" => "any" }
          end
        end

        # Parse array type definition
        def parse_array_type(array_value)
          if array_value.empty?
            { "type" => "array", "items" => {} }
          elsif array_value.first.is_a?(Hash)
            # Array of objects with nested schema
            { "type" => "array", "items" => parse_object(array_value.first) }
          else
            # Array of scalar type
            { "type" => "array", "items" => parse_type_string(array_value.first.to_s) }
          end
        end

        # Parse the type part (before the comma)
        def parse_type_part(type_part)
          # Handle array shorthand: [string] or [object]
          if type_part.start_with?("[") && type_part.end_with?("]")
            inner = type_part[1..-2].strip
            if inner == "object"
              return { "type" => "array", "items" => { "type" => "object" } }
            else
              return { "type" => "array", "items" => parse_type_part(inner) }
            end
          end

          # Handle enum: string(option1, option2, option3)
          if type_part =~ /\A(\w+)\((.+)\)\z/
            base_type = ::Regexp.last_match(1)
            enum_str = ::Regexp.last_match(2)
            enum_values = parse_enum_values(enum_str)
            return { "type" => base_type, "enum" => enum_values }
          end

          # Handle nested object reference
          if type_part == "object"
            return { "type" => "object" }
          end

          # Handle scalar types
          if SCALAR_TYPES.include?(type_part.downcase)
            return { "type" => type_part.downcase }
          end

          # Unknown type - preserve as-is
          { "type" => type_part }
        end

        # Parse enum values from string like "option1, option2, option3"
        def parse_enum_values(enum_str)
          enum_str.split(",").map do |val|
            val = val.strip
            # Remove quotes if present
            val = val.gsub(/\A["']|["']\z/, "")
            val
          end
        end

        # Convert JSON Schema properties to Picoschema format
        def convert_properties(properties, required_fields)
          result = {}

          properties.each do |name, schema|
            optional = !required_fields.include?(name.to_s)
            key = optional ? "#{name}?" : name.to_s
            result[key] = convert_schema_to_pico(schema)
          end

          result
        end

        # Convert a single JSON Schema field to Picoschema string
        def convert_schema_to_pico(schema)
          type = schema["type"] || schema[:type]
          desc = schema["description"] || schema[:description]
          enum_values = schema["enum"] || schema[:enum]

          # Handle array types
          if type == "array"
            items = schema["items"] || schema[:items] || {}
            items_type = items["type"] || items[:type] || "any"
            if items_type == "object"
              # Complex - return as hash
              return [convert_properties(items["properties"] || {}, items["required"] || [])]
            else
              return "[#{items_type}]"
            end
          end

          # Handle object types
          if type == "object" && (schema["properties"] || schema[:properties])
            return convert_properties(
              schema["properties"] || schema[:properties],
              schema["required"] || schema[:required] || []
            )
          end

          # Build picoschema string
          pico = type.to_s
          if enum_values&.any?
            pico = "#{type}(#{enum_values.join(", ")})"
          end
          if desc.present?
            pico = "#{pico}, #{desc}"
          end

          pico
        end
      end
    end
  end
end

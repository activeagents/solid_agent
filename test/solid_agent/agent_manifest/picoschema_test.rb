# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    class PicoschemaTest < Minitest::Test
      def test_simple_string_field
        picoschema = { "name" => "string" }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "object", json_schema["type"]
        assert_equal "string", json_schema["properties"]["name"]["type"]
        assert_includes json_schema["required"], "name"
      end

      def test_string_with_description
        picoschema = { "query" => "string, The search query" }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "string", json_schema["properties"]["query"]["type"]
        assert_equal "The search query", json_schema["properties"]["query"]["description"]
      end

      def test_optional_field
        picoschema = { "limit?" => "integer" }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "integer", json_schema["properties"]["limit"]["type"]
        # Required array might be nil or empty, either way "limit" shouldn't be required
        required = json_schema["required"] || []
        refute_includes required, "limit"
      end

      def test_enum_type
        picoschema = { "status" => "string(pending, active, completed)" }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "string", json_schema["properties"]["status"]["type"]
        assert_equal %w[pending active completed], json_schema["properties"]["status"]["enum"]
      end

      def test_array_type
        picoschema = { "tags" => "[string]" }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "array", json_schema["properties"]["tags"]["type"]
        assert_equal "string", json_schema["properties"]["tags"]["items"]["type"]
      end

      def test_nested_object
        picoschema = {
          "user" => {
            "name" => "string",
            "email?" => "string"
          }
        }
        json_schema = Picoschema.to_json_schema(picoschema)

        assert_equal "object", json_schema["properties"]["user"]["type"]
        assert_equal "string", json_schema["properties"]["user"]["properties"]["name"]["type"]
        assert_equal "string", json_schema["properties"]["user"]["properties"]["email"]["type"]
        assert_includes json_schema["properties"]["user"]["required"], "name"
        user_required = json_schema["properties"]["user"]["required"] || []
        refute_includes user_required, "email"
      end

      def test_from_json_schema_simple
        json_schema = {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string", "description" => "User name" }
          },
          "required" => ["name"]
        }

        picoschema = Picoschema.from_json_schema(json_schema)

        assert_equal "string, User name", picoschema["name"]
      end

      def test_from_json_schema_optional
        json_schema = {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string" },
            "age" => { "type" => "integer" }
          },
          "required" => ["name"]
        }

        picoschema = Picoschema.from_json_schema(json_schema)

        assert_equal "string", picoschema["name"]
        assert_equal "integer", picoschema["age?"]
      end

      def test_from_json_schema_enum
        json_schema = {
          "type" => "object",
          "properties" => {
            "status" => {
              "type" => "string",
              "enum" => %w[draft published]
            }
          },
          "required" => ["status"]
        }

        picoschema = Picoschema.from_json_schema(json_schema)

        assert_equal "string(draft, published)", picoschema["status"]
      end

      def test_round_trip_conversion
        original = {
          "query" => "string, Search query",
          "limit?" => "integer",
          "format" => "string(web, image, news)"
        }

        json_schema = Picoschema.to_json_schema(original)
        back = Picoschema.from_json_schema(json_schema)

        # Required fields should have no suffix
        assert_equal original["query"], back["query"]
        # Optional fields should have ? suffix
        assert_equal original["limit?"], back["limit?"]
        # Check enum format - using "format" instead of "type" to avoid confusion
        assert_equal original["format"], back["format"]
      end
    end
  end
end

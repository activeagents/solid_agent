# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    class ValidatorTest < Minitest::Test
      def test_valid_manifest
        manifest = Manifest.new(
          name: "test-agent",
          model: "anthropic/claude-sonnet",
          instructions: "Help users."
        )

        errors = Validator.validate(manifest)

        assert_empty errors
      end

      def test_validates_name_required
        manifest = Manifest.new(instructions: "Content")

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("name is required") }
      end

      def test_validates_name_format
        manifest = Manifest.new(
          name: "Invalid Name!",
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("must start with lowercase") }
      end

      def test_validates_reserved_names
        manifest = Manifest.new(
          name: "agent",
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("reserved") }
      end

      def test_validates_version_semver
        manifest = Manifest.new(
          name: "test",
          version: "invalid",
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("semantic versioning") }
      end

      def test_validates_temperature_range
        manifest = Manifest.new(
          name: "test",
          model: "anthropic/claude-sonnet",
          config: { "temperature" => 3.0 },
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("temperature") }, "Expected temperature validation error, got: #{errors.inspect}"
      end

      def test_validates_tool_names
        tool = Tool.new(name: "invalid name", description: "Test")
        manifest = Manifest.new(
          name: "test",
          tools: [tool],
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("must start with letter") }
      end

      def test_validates_duplicate_tool_names
        tool1 = Tool.new(name: "search", description: "Search")
        tool2 = Tool.new(name: "search", description: "Also search")
        manifest = Manifest.new(
          name: "test",
          tools: [tool1, tool2],
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("duplicate tool name") }
      end

      def test_validates_content_present
        manifest = Manifest.new(name: "test")

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("must have instructions or template") }
      end

      def test_valid_returns_boolean
        valid_manifest = Manifest.new(name: "test", instructions: "Content")
        invalid_manifest = Manifest.new

        assert Validator.valid?(valid_manifest)
        refute Validator.valid?(invalid_manifest)
      end

      def test_validate_bang_raises_on_invalid
        manifest = Manifest.new

        assert_raises(ValidationError) do
          Validator.validate!(manifest)
        end
      end

      def test_validate_bang_returns_manifest_on_valid
        manifest = Manifest.new(name: "test", instructions: "Content")

        result = Validator.validate!(manifest)

        assert_equal manifest, result
      end

      def test_strict_mode_requires_description
        manifest = Manifest.new(
          name: "test",
          model: "anthropic/claude",
          instructions: "Content"
        )

        normal_errors = Validator.validate(manifest)
        strict_errors = Validator.validate(manifest, strict: true)

        refute normal_errors.any? { |e| e.include?("description") }
        assert strict_errors.any? { |e| e.include?("description is required") }
      end

      def test_strict_mode_requires_model
        manifest = Manifest.new(
          name: "test",
          description: "Test agent",
          instructions: "Content"
        )

        errors = Validator.validate(manifest, strict: true)

        assert errors.any? { |e| e.include?("model is required") }
      end

      def test_validates_repository_url
        manifest = Manifest.new(
          name: "test",
          repository: "not-a-url",
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("repository must be a valid URL") }
      end

      def test_validates_resource_uri
        resource = Resource.new(name: "data", uri: "invalid")
        manifest = Manifest.new(
          name: "test",
          resources: [resource],
          instructions: "Content"
        )

        errors = Validator.validate(manifest)

        assert errors.any? { |e| e.include?("uri must be a valid URI") }
      end
    end
  end
end

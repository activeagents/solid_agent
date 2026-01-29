# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    class ManifestTest < Minitest::Test
      def test_manifest_with_valid_attributes
        manifest = Manifest.new(
          name: "test-agent",
          version: "1.0.0",
          description: "A test agent",
          model: "anthropic/claude-sonnet-4-20250514"
        )

        assert manifest.valid?
        assert_equal "test-agent", manifest.name
        assert_equal "1.0.0", manifest.version
        assert_equal "anthropic/claude-sonnet-4-20250514", manifest.model
      end

      def test_manifest_requires_name
        manifest = Manifest.new(version: "1.0.0")

        refute manifest.valid?
        assert_includes manifest.errors[:name], "can't be blank"
      end

      def test_manifest_validates_name_format
        manifest = Manifest.new(name: "Invalid Name")

        refute manifest.valid?
        assert manifest.errors[:name].any? { |e| e.include?("lowercase") }
      end

      def test_manifest_validates_version_format
        manifest = Manifest.new(name: "test", version: "invalid")

        refute manifest.valid?
        assert manifest.errors[:version].any? { |e| e.include?("semver") }
      end

      def test_manifest_accepts_semver_with_prerelease
        manifest = Manifest.new(name: "test", version: "1.0.0-beta.1")

        assert manifest.valid?
      end

      def test_manifest_defaults
        manifest = Manifest.new(name: "test")

        assert_equal "1.0.0", manifest.version
        assert_equal [], manifest.tags
        assert_equal [], manifest.tools
        assert_equal [], manifest.resources
        assert_equal({}, manifest.extensions)
        assert_equal({}, manifest.config)
      end

      def test_manifest_to_h
        manifest = Manifest.new(
          name: "test-agent",
          description: "Test",
          model: "anthropic/claude-sonnet"
        )

        hash = manifest.to_h

        assert_equal "test-agent", hash[:name]
        assert_equal "Test", hash[:description]
        assert_equal "anthropic/claude-sonnet", hash[:model]
      end

      def test_manifest_framework_accessors
        manifest = Manifest.new(
          name: "test",
          extensions: {
            activeagent: { class_name: "TestAgent" },
            crewai: { role: "Researcher" }
          }
        )

        assert_equal({ class_name: "TestAgent" }, manifest.activeagent_config)
        assert_equal({ role: "Researcher" }, manifest.crewai_config)
      end
    end
  end
end

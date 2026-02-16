# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    module Parsers
      class AgentMdParserTest < Minitest::Test
        def fixture_path(name)
          File.expand_path("../../../../fixtures/agent_manifest/valid/#{name}", __FILE__)
        end

        def test_parse_minimal
          manifest = AgentMdParser.parse(fixture_path("minimal.agent.md"))

          assert_equal "minimal-agent", manifest.name
          assert_equal :agent_md, manifest.source_format
        end

        def test_parse_full_featured
          manifest = AgentMdParser.parse(fixture_path("full_featured.agent.md"))

          assert_equal "research-assistant", manifest.name
          assert_equal "2.1.0", manifest.version
          assert_equal "ActiveAgents Team", manifest.author
          assert_equal "MIT", manifest.license
          assert_includes manifest.tags, "research"
          assert_equal "anthropic/claude-sonnet-4-20250514", manifest.model
          assert_equal 0.7, manifest.config[:temperature] || manifest.config["temperature"]
          assert_equal 2, manifest.tools.size
          assert_equal 1, manifest.resources.size
        end

        def test_parse_with_tools
          manifest = AgentMdParser.parse(fixture_path("with_tools.agent.md"))

          assert_equal "tool-agent", manifest.name
          assert_equal 3, manifest.tools.size

          calc_tool = manifest.tools.find { |t| t.name == "calculate" }
          assert_equal "Perform mathematical calculations", calc_tool.description
          assert_equal "object", calc_tool.input_schema["type"]

          ref_tool = manifest.tools.find(&:reference?)
          assert ref_tool.ref.include?("common_tools")
        end

        def test_parse_string
          content = <<~AGENTMD
            ---
            name: string-parsed
            model: openai/gpt-4
            ---

            # Test Agent

            Instructions here.
          AGENTMD

          manifest = AgentMdParser.parse_string(content)

          assert_equal "string-parsed", manifest.name
          assert_equal "openai/gpt-4", manifest.model
          assert_includes manifest.template, "Instructions here"
        end

        def test_parse_with_activeagent_extensions
          content = <<~AGENTMD
            ---
            name: extended-agent
            activeagent:
              class_name: CustomAgent
              concerns:
                - has_context:
                    contextual: user
                - has_tools
            ---

            Test content.
          AGENTMD

          manifest = AgentMdParser.parse_string(content)

          assert_equal "CustomAgent", manifest.extensions[:activeagent]["class_name"]
          assert_equal 2, manifest.extensions[:activeagent]["concerns"].size
        end

        def test_parse_without_frontmatter
          content = "# Just Markdown\n\nNo frontmatter here."

          manifest = AgentMdParser.parse_string(content)

          assert_nil manifest.name
          assert_includes manifest.template, "No frontmatter here"
        end

        def test_parse_malformed_frontmatter_raises
          content = <<~BAD
            ---
            name: test
            invalid yaml: [
            ---

            Content
          BAD

          assert_raises(ParseError) do
            AgentMdParser.parse_string(content)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    module Parsers
      class CrewAIParserTest < Minitest::Test
        def fixture_path(name)
          File.expand_path("../../../../fixtures/agent_manifest/crewai/#{name}", __FILE__)
        end

        def test_parse_multiple_agents
          result = CrewAIParser.parse(fixture_path("agents.yaml"))

          # Should return array for multiple agents
          assert_kind_of Array, result
          assert_equal 2, result.size
        end

        def test_parse_agent_names
          result = CrewAIParser.parse(fixture_path("agents.yaml"))

          names = result.map(&:name)
          assert_includes names, "research-analyst"
          assert_includes names, "reporting-analyst"
        end

        def test_parse_agent_model
          result = CrewAIParser.parse(fixture_path("agents.yaml"))

          research = result.find { |m| m.name == "research-analyst" }
          assert_equal "anthropic/claude-sonnet-4-20250514", research.model
        end

        def test_parse_agent_tools
          result = CrewAIParser.parse(fixture_path("agents.yaml"))

          research = result.find { |m| m.name == "research-analyst" }
          assert_equal 2, research.tools.size
          assert research.tools.all?(&:reference?)
        end

        def test_parse_crewai_extensions
          result = CrewAIParser.parse(fixture_path("agents.yaml"))

          research = result.find { |m| m.name == "research-analyst" }
          crewai_ext = research.extensions[:crewai]

          assert_includes crewai_ext[:role], "Senior Research Analyst"
          assert_includes crewai_ext[:goal], "cutting-edge developments"
          assert crewai_ext[:verbose]
          assert_equal false, crewai_ext[:allow_delegation]
        end

        def test_parse_string_single_agent
          content = <<~YAML
            assistant:
              role: General Assistant
              goal: Help users with tasks
              backstory: You are a helpful assistant.
              llm: gpt-4o
          YAML

          manifest = CrewAIParser.parse_string(content)

          # Single agent returns manifest directly (not array)
          assert_kind_of Manifest, manifest
          assert_equal "assistant", manifest.name
          assert_equal "openai/gpt-4o", manifest.model
        end

        def test_builds_instructions_from_role_and_backstory
          content = <<~YAML
            writer:
              role: Technical Writer
              goal: Create documentation
              backstory: Expert at technical writing.
          YAML

          manifest = CrewAIParser.parse_string(content)

          assert_includes manifest.instructions, "Role: Technical Writer"
          assert_includes manifest.instructions, "Goal: Create documentation"
          assert_includes manifest.instructions, "Expert at technical writing"
        end

        def test_normalize_snake_case_to_kebab
          content = <<~YAML
            data_processor:
              role: Data Processor
              goal: Process data
          YAML

          manifest = CrewAIParser.parse_string(content)

          assert_equal "data-processor", manifest.name
        end
      end
    end
  end
end

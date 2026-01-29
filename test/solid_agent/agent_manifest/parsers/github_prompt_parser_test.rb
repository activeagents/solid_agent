# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    module Parsers
      class GitHubPromptParserTest < Minitest::Test
        def fixture_path(name)
          File.expand_path("../../../../fixtures/agent_manifest/github_prompt/#{name}", __FILE__)
        end

        def test_parse_github_prompt
          manifest = GitHubPromptParser.parse(fixture_path("copilot.prompt.md"))

          assert_equal :github_prompt, manifest.source_format
          assert_equal "openai/gpt-4o", manifest.model
        end

        def test_parse_tools_as_references
          manifest = GitHubPromptParser.parse(fixture_path("copilot.prompt.md"))

          assert_equal 3, manifest.tools.size
          assert manifest.tools.all?(&:reference?)

          refs = manifest.tools.map(&:ref)
          assert_includes refs, "github://githubRepo"
          assert_includes refs, "github://search/codebase"
        end

        def test_parse_description
          manifest = GitHubPromptParser.parse(fixture_path("copilot.prompt.md"))

          assert_equal "Generate a new React form component with validation", manifest.description
        end

        def test_parse_github_extensions
          manifest = GitHubPromptParser.parse(fixture_path("copilot.prompt.md"))

          github_ext = manifest.extensions[:github_prompt]
          assert_equal "agent", github_ext[:mode]
          assert github_ext[:original_tools]
        end

        def test_parse_string
          content = <<~PROMPT
            ---
            model: GPT-4
            tools: ['search', 'fetch']
            description: 'Simple prompt'
            ---

            Generate code for ${input:feature}
          PROMPT

          manifest = GitHubPromptParser.parse_string(content)

          assert_equal "openai/gpt-4", manifest.model
          assert_equal 2, manifest.tools.size
          assert_equal "Simple prompt", manifest.description
        end

        def test_extract_name_from_description
          content = <<~PROMPT
            ---
            description: 'Generate React Components'
            ---

            Content here.
          PROMPT

          manifest = GitHubPromptParser.parse_string(content)

          assert_equal "generate-react-components", manifest.name
        end

        def test_extract_name_from_heading
          content = <<~PROMPT
            ---
            model: GPT-4
            ---

            # API Generator

            Generate API endpoints.
          PROMPT

          manifest = GitHubPromptParser.parse_string(content)

          assert_equal "api-generator", manifest.name
        end

        def test_normalize_github_model_names
          test_cases = [
            ["GPT-4o", "openai/gpt-4o"],
            ["gpt4o", "openai/gpt-4o"],
            ["GPT-4", "openai/gpt-4"],
            ["gpt-3.5-turbo", "openai/gpt-3.5-turbo"],
            ["claude-3-opus", "anthropic/claude-3-opus"]
          ]

          test_cases.each do |input, expected|
            content = <<~PROMPT
              ---
              model: #{input}
              ---

              Test
            PROMPT

            manifest = GitHubPromptParser.parse_string(content)
            assert_equal expected, manifest.model, "Expected #{input} to normalize to #{expected}"
          end
        end
      end
    end
  end
end

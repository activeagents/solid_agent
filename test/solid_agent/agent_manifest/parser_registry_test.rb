# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    class ParserRegistryTest < Minitest::Test
      def test_detect_format_agent_md
        assert_equal :agent_md, ParserRegistry.detect_format("agent.agent.md")
        assert_equal :agent_md, ParserRegistry.detect_format("/path/to/my-agent.agent.md")
      end

      def test_detect_format_dotprompt
        assert_equal :dotprompt, ParserRegistry.detect_format("translate.prompt")
        assert_equal :dotprompt, ParserRegistry.detect_format("/prompts/basic.prompt")
      end

      def test_detect_format_crewai
        assert_equal :crewai, ParserRegistry.detect_format("agents.yaml")
        assert_equal :crewai, ParserRegistry.detect_format("agents.yml")
        assert_equal :crewai, ParserRegistry.detect_format("/config/crew_agents.yaml")
      end

      def test_detect_format_github_prompt
        assert_equal :github_prompt, ParserRegistry.detect_format("component.prompt.md")
        assert_equal :github_prompt, ParserRegistry.detect_format("/copilot/generate.prompt.md")
      end

      def test_detect_format_unknown
        assert_raises(UnknownFormatError) do
          ParserRegistry.detect_format("unknown.txt")
        end
      end

      def test_registered_formats
        formats = ParserRegistry.formats

        assert_includes formats, :agent_md
        assert_includes formats, :dotprompt
        assert_includes formats, :crewai
        assert_includes formats, :github_prompt
      end

      def test_supports_format
        assert ParserRegistry.supports?(:agent_md)
        assert ParserRegistry.supports?(:dotprompt)
        refute ParserRegistry.supports?(:unknown_format)
      end

      def test_parser_for_format
        parser = ParserRegistry.parser_for(:agent_md)
        assert_equal Parsers::AgentMdParser, parser
      end

      def test_parser_for_unknown_format
        assert_raises(UnknownFormatError) do
          ParserRegistry.parser_for(:unknown)
        end
      end
    end
  end
end

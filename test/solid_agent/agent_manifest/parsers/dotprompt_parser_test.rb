# frozen_string_literal: true

require "test_helper"

module SolidAgent
  module AgentManifest
    module Parsers
      class DotpromptParserTest < Minitest::Test
        def fixture_path(name)
          File.expand_path("../../../../fixtures/agent_manifest/dotprompt/#{name}", __FILE__)
        end

        def test_parse_basic_prompt
          manifest = DotpromptParser.parse(fixture_path("basic.prompt"))

          assert_equal :dotprompt, manifest.source_format
          assert_equal "googleai/gemini-1.5-pro", manifest.model
          assert_equal 0.7, manifest.config[:temperature] || manifest.config["temperature"]
          assert_equal 2048, manifest.config[:max_tokens] || manifest.config["max_tokens"]
        end

        def test_parse_input_schema
          manifest = DotpromptParser.parse(fixture_path("basic.prompt"))

          assert manifest.input_schema
          json_schema = manifest.input_schema.to_json_schema

          assert_equal "string", json_schema["properties"]["text"]["type"]
          assert_includes json_schema["required"], "text"
          refute_includes json_schema["required"], "language"
        end

        def test_parse_output_schema
          manifest = DotpromptParser.parse(fixture_path("basic.prompt"))

          assert manifest.output_schema
          format = manifest.output_schema["format"] || manifest.output_schema[:format]
          assert_equal "json", format
          assert manifest.output_schema["schema"] || manifest.output_schema[:schema]
        end

        def test_parse_tools
          manifest = DotpromptParser.parse(fixture_path("basic.prompt"))

          assert_equal 2, manifest.tools.size
          assert manifest.tools.all?(&:reference?)
        end

        def test_parse_string
          content = <<~DOTPROMPT
            ---
            model: openai/gpt-4
            temperature: 0.5
            ---

            Summarize: {{ text }}
          DOTPROMPT

          manifest = DotpromptParser.parse_string(content)

          assert_equal "openai/gpt-4", manifest.model
          assert_equal 0.5, manifest.config[:temperature] || manifest.config["temperature"]
          assert_includes manifest.template, "{{ text }}"
        end

        def test_model_normalization
          content = <<~DOTPROMPT
            ---
            model: gemini-1.5-pro
            ---

            Content
          DOTPROMPT

          manifest = DotpromptParser.parse_string(content)

          # Should normalize to include provider
          assert manifest.model.include?("/")
        end

        def test_generate_name_from_content
          content = <<~DOTPROMPT
            ---
            model: openai/gpt-4
            ---

            # Translation Helper

            Translate the text.
          DOTPROMPT

          manifest = DotpromptParser.parse_string(content)

          assert_equal "translation-helper", manifest.name
        end
      end
    end
  end
end

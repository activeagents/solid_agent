# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Parsers
      # AgentMdParser handles the native .agent.md format.
      #
      # This is the primary format for ActiveAgent manifests, featuring
      # YAML frontmatter with comprehensive metadata and a Markdown body
      # containing instructions and Liquid templates.
      #
      # @example Basic .agent.md file
      #   ---
      #   name: research-assistant
      #   model: anthropic/claude-sonnet-4-20250514
      #   ---
      #
      #   # Research Assistant
      #
      #   You help users research topics thoroughly.
      #
      class AgentMdParser < BaseParser
        class << self
          def format_name
            :agent_md
          end

          def parse_string(content)
            frontmatter, body = extract_frontmatter(content)

            Manifest.new(
              # Meta
              name: frontmatter["name"],
              version: frontmatter["version"],
              description: frontmatter["description"],
              author: frontmatter["author"],
              license: frontmatter["license"],
              repository: frontmatter["repository"],
              tags: parse_tags(frontmatter["tags"]),
              extends: frontmatter["extends"],

              # Model
              model: normalize_model(frontmatter["model"]),
              config: parse_config(frontmatter),

              # Schemas
              input_schema: parse_input_schema(frontmatter["input"]),
              output_schema: frontmatter["output"],

              # Tools & Resources
              tools: parse_tools(frontmatter["tools"]),
              resources: parse_resources(frontmatter["resources"]),

              # Instructions
              instructions: extract_instructions(body),
              template: body.presence,

              # Extensions
              extensions: extract_extensions(frontmatter),

              # Examples & Tests
              examples: frontmatter["examples"] || [],
              tests: frontmatter["tests"] || []
            )
          end

          private

          # Parse tags ensuring array format
          def parse_tags(tags_data)
            case tags_data
            when Array
              tags_data.map(&:to_s)
            when String
              tags_data.split(",").map(&:strip)
            else
              []
            end
          end
        end
      end

      # Register the parser
      ParserRegistry.register(:agent_md, AgentMdParser)
    end
  end
end

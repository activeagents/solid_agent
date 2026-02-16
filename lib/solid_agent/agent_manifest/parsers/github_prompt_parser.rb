# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Parsers
      # GitHubPromptParser handles GitHub Copilot's .prompt.md format.
      #
      # GitHub Copilot prompt files use Markdown with YAML frontmatter,
      # supporting variables, tool references, and agent configuration.
      #
      # @see https://docs.github.com/en/copilot/tutorials/customization-library/prompt-files
      #
      # @example .prompt.md file
      #   ---
      #   model: GPT-4o
      #   tools: ['githubRepo', 'search/codebase']
      #   description: 'Generate a new React form component'
      #   ---
      #
      #   Create a React form component for ${input:formName}
      #
      class GitHubPromptParser < BaseParser
        class << self
          def format_name
            :github_prompt
          end

          def parse_string(content)
            frontmatter, body = extract_frontmatter(content)

            Manifest.new(
              name: extract_name(frontmatter, body),
              description: frontmatter["description"],
              version: "1.0.0",

              # Model
              model: normalize_github_model(frontmatter["model"]),
              config: {},

              # Tools are GitHub-specific references
              tools: parse_github_tools(frontmatter["tools"]),

              # Template with GitHub variable syntax
              instructions: body,
              template: body,

              # Preserve GitHub-specific config
              extensions: {
                github_prompt: extract_github_extensions(frontmatter)
              }
            )
          end

          private

          # Extract name from frontmatter or generate from content
          def extract_name(frontmatter, body)
            return frontmatter["name"] if frontmatter["name"].present?

            # Try to extract from description
            if frontmatter["description"].present?
              return frontmatter["description"]
                .downcase
                .gsub(/[^a-z0-9\s-]/, "")
                .gsub(/\s+/, "-")
                .slice(0, 50)
            end

            # Try to extract from first heading
            if body =~ /\A#\s+(.+)/
              return ::Regexp.last_match(1)
                .strip
                .downcase
                .gsub(/[^a-z0-9\s-]/, "")
                .gsub(/\s+/, "-")
            end

            "github-prompt"
          end

          # Normalize GitHub model names
          def normalize_github_model(model)
            return nil unless model.present?

            model_str = model.to_s.strip

            # GitHub uses simplified model names
            case model_str.downcase
            when "gpt-4o", "gpt4o"
              "openai/gpt-4o"
            when "gpt-4", "gpt4"
              "openai/gpt-4"
            when "gpt-3.5-turbo", "gpt35turbo"
              "openai/gpt-3.5-turbo"
            when /\Aclaude/
              "anthropic/#{model_str.downcase}"
            else
              normalize_model(model_str)
            end
          end

          # Parse GitHub tool references
          def parse_github_tools(tools_data)
            return [] unless tools_data.is_a?(Array)

            tools_data.map do |tool|
              tool_name = tool.to_s
              Tool.new(ref: "github://#{tool_name}")
            end
          end

          # Extract GitHub-specific extensions
          def extract_github_extensions(frontmatter)
            {
              agent: frontmatter["agent"],
              mode: frontmatter["mode"],
              variables: extract_variables(frontmatter),
              # Preserve any other GitHub-specific fields
              original_tools: frontmatter["tools"]
            }.compact
          end

          # Extract variable definitions
          def extract_variables(frontmatter)
            variables = {}

            # GitHub prompts can define input variables
            frontmatter.each do |key, value|
              next unless key.to_s.start_with?("input:")
              var_name = key.to_s.sub("input:", "")
              variables[var_name] = value
            end

            variables.presence
          end
        end
      end

      # Register the parser
      ParserRegistry.register(:github_prompt, GitHubPromptParser)
    end
  end
end

# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Parsers
      # DotpromptParser handles Google Genkit's .prompt format.
      #
      # Dotprompt files use YAML frontmatter with Handlebars-style templates.
      # This parser converts them to the unified Manifest format.
      #
      # @see https://github.com/google/dotprompt
      #
      # @example Basic .prompt file
      #   ---
      #   model: googleai/gemini-1.5-pro
      #   input:
      #     schema:
      #       text: string
      #   output:
      #     format: json
      #   ---
      #
      #   Extract information from: {{text}}
      #
      class DotpromptParser < BaseParser
        class << self
          def format_name
            :dotprompt
          end

          def parse_string(content)
            frontmatter, body = extract_frontmatter(content)

            # Extract name from frontmatter or generate from content
            name = frontmatter["name"] || generate_name_from_content(body)

            Manifest.new(
              name: name,
              version: frontmatter["version"] || "1.0.0",
              description: frontmatter["description"],

              # Model - Dotprompt format
              model: normalize_model(frontmatter["model"]),
              config: parse_dotprompt_config(frontmatter),

              # Schemas
              input_schema: parse_input_schema(frontmatter["input"]),
              output_schema: parse_output_schema(frontmatter["output"]),

              # Tools (Dotprompt can reference tools)
              tools: parse_tools(frontmatter["tools"]),

              # Template
              instructions: body,
              template: body,

              # Store original Dotprompt config in extensions
              extensions: {
                dotprompt: extract_dotprompt_extensions(frontmatter)
              }
            )
          end

          private

          # Generate a name from template content
          def generate_name_from_content(body)
            # Try to extract from first line/heading
            if body =~ /\A#\s+(.+)/
              ::Regexp.last_match(1).strip.downcase.gsub(/\s+/, "-").gsub(/[^a-z0-9-]/, "")
            else
              "unnamed-prompt"
            end
          end

          # Parse Dotprompt-specific config fields
          def parse_dotprompt_config(frontmatter)
            config = {}

            # Map Dotprompt field names to normalized names
            config[:temperature] = frontmatter["temperature"] if frontmatter["temperature"]
            config[:max_tokens] = frontmatter["maxOutputTokens"] if frontmatter["maxOutputTokens"]
            config[:top_p] = frontmatter["topP"] if frontmatter["topP"]
            config[:top_k] = frontmatter["topK"] if frontmatter["topK"]
            config[:stop] = frontmatter["stopSequences"] if frontmatter["stopSequences"]

            # Also support normalized names
            config[:temperature] ||= frontmatter["config"]&.dig("temperature")
            config[:max_tokens] ||= frontmatter["config"]&.dig("max_tokens")

            config.compact
          end

          # Parse Dotprompt output schema
          def parse_output_schema(output_data)
            return nil unless output_data.is_a?(Hash)

            {
              format: output_data["format"],
              schema: output_data["schema"]
            }.compact.presence
          end

          # Extract Dotprompt-specific extensions that don't map to standard fields
          def extract_dotprompt_extensions(frontmatter)
            extensions = {}

            # Preserve Dotprompt-specific fields
            %w[candidates cache default variant metadata].each do |key|
              extensions[key] = frontmatter[key] if frontmatter[key].present?
            end

            extensions.presence
          end
        end
      end

      # Register the parser
      ParserRegistry.register(:dotprompt, DotpromptParser)
    end
  end
end

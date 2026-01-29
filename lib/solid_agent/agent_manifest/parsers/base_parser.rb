# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Parsers
      # BaseParser provides common functionality for all format parsers.
      #
      # Subclasses should implement:
      # - .parse_string(content) - Parse content string into a Manifest
      # - .format_name - Return the format identifier symbol
      #
      class BaseParser
        FRONTMATTER_REGEX = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

        class << self
          # Parse a file into a Manifest
          #
          # @param path [String] Path to the file
          # @return [Manifest] Parsed manifest
          def parse(path)
            content = File.read(path, encoding: "UTF-8")
            manifest = parse_string(content)

            # Handle array results (e.g., CrewAI with multiple agents)
            if manifest.is_a?(Array)
              manifest.each do |m|
                m.source_path = path
                m.source_format = format_name
              end
            else
              manifest.source_path = path
              manifest.source_format = format_name
            end

            manifest
          end

          # Parse content string into a Manifest
          #
          # @param content [String] File content
          # @return [Manifest] Parsed manifest
          def parse_string(content)
            raise NotImplementedError, "#{self}.parse_string must be implemented by subclass"
          end

          # Get the format name for this parser
          #
          # @return [Symbol]
          def format_name
            raise NotImplementedError, "#{self}.format_name must be implemented by subclass"
          end

          protected

          # Extract YAML frontmatter from markdown content
          #
          # @param content [String] Full content with frontmatter
          # @return [Array<Hash, String>] [frontmatter_hash, body]
          def extract_frontmatter(content)
            return [{}, content.strip] if content.blank?

            match = content.match(FRONTMATTER_REGEX)

            unless match
              # Check if frontmatter was intended but malformed
              if content.strip.start_with?("---")
                raise ParseError, "Malformed frontmatter: missing closing '---' delimiter"
              end
              return [{}, content.strip]
            end

            begin
              frontmatter = YAML.safe_load(
                match[1],
                permitted_classes: [Symbol, Date, Time],
                permitted_symbols: [],
                aliases: false
              )
            rescue Psych::SyntaxError => e
              raise ParseError, "Invalid YAML in frontmatter: #{e.message}"
            end

            [frontmatter || {}, match[2].strip]
          end

          # Normalize model identifier to provider/model format
          #
          # @param model_string [String, nil] Model identifier
          # @return [String, nil] Normalized model identifier
          def normalize_model(model_string)
            return nil unless model_string.present?

            model_string = model_string.to_s.strip

            # Already in provider/model format
            return model_string if model_string.include?("/")

            # Detect provider from model name
            if model_string.start_with?("gpt-") || model_string.start_with?("o1") || model_string.start_with?("o3")
              "openai/#{model_string}"
            elsif model_string.start_with?("claude-")
              "anthropic/#{model_string}"
            elsif model_string.start_with?("gemini-")
              "google/#{model_string}"
            elsif model_string.start_with?("llama") || model_string.start_with?("mixtral")
              "meta/#{model_string}"
            else
              # Unknown - return as-is
              model_string
            end
          end

          # Parse tools array from frontmatter data
          #
          # @param tools_data [Array, nil] Tools data from frontmatter
          # @return [Array<Tool>] Parsed tools
          def parse_tools(tools_data)
            return [] unless tools_data.is_a?(Array)

            tools_data.map do |tool_data|
              if tool_data.is_a?(String)
                # String reference
                Tool.new(ref: tool_data)
              elsif tool_data["$ref"]
                # Explicit reference
                Tool.new(ref: tool_data["$ref"])
              else
                # Inline definition
                Tool.from_hash(tool_data)
              end
            end
          end

          # Parse resources array from frontmatter data
          #
          # @param resources_data [Array, nil] Resources data from frontmatter
          # @return [Array<Resource>] Parsed resources
          def parse_resources(resources_data)
            return [] unless resources_data.is_a?(Array)

            resources_data.map { |data| Resource.from_hash(data) }
          end

          # Parse input schema from frontmatter data
          #
          # @param input_data [Hash, nil] Input schema data
          # @return [InputSchema, nil] Parsed input schema
          def parse_input_schema(input_data)
            return nil unless input_data.is_a?(Hash)

            schema = input_data["schema"] || input_data[:schema]
            return nil unless schema

            format = InputSchema.detect_format(schema)
            InputSchema.new(schema: schema, format: format)
          end

          # Extract framework extensions from frontmatter
          #
          # @param frontmatter [Hash] Full frontmatter hash
          # @return [Hash] Framework extensions
          def extract_extensions(frontmatter)
            extensions = {}

            %w[activeagent crewai langchain genkit dotprompt].each do |framework|
              value = frontmatter[framework] || frontmatter[framework.to_sym]
              extensions[framework.to_sym] = value if value.present?
            end

            extensions
          end

          # Extract instructions from markdown body
          #
          # @param body [String] Markdown body
          # @return [String, nil] Extracted instructions
          def extract_instructions(body)
            return nil if body.blank?

            # Try to find ## Instructions section
            if body =~ /##\s*Instructions\s*\n(.*?)(?=\n##|\z)/mi
              return ::Regexp.last_match(1).strip
            end

            # Try ## Instruct (abbreviated)
            if body =~ /##\s*Instruct\w*\s*\n(.*?)(?=\n##|\z)/mi
              return ::Regexp.last_match(1).strip
            end

            # Fall back to body without title
            body.gsub(/\A#\s+[^\n]+\n+/, "").strip.presence
          end

          # Parse config/model parameters
          #
          # @param frontmatter [Hash] Frontmatter hash
          # @return [Hash] Config hash
          def parse_config(frontmatter)
            config = frontmatter["config"] || frontmatter[:config] || {}

            # Also check for top-level config keys (Dotprompt style)
            %w[temperature max_tokens maxOutputTokens top_p topP top_k topK stop stopSequences].each do |key|
              value = frontmatter[key] || frontmatter[key.to_sym]
              if value.present?
                # Normalize key names
                normalized_key = case key
                when "maxOutputTokens" then "max_tokens"
                when "topP" then "top_p"
                when "topK" then "top_k"
                when "stopSequences" then "stop"
                else key
                end
                config[normalized_key] = value
              end
            end

            config.presence || {}
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # ParserRegistry manages format parsers and provides format detection.
    #
    # It enables automatic detection of file formats and routes parsing
    # to the appropriate parser class.
    #
    # @example Parsing a file
    #   manifest = ParserRegistry.parse("agent.agent.md")
    #   manifest = ParserRegistry.parse("agent.prompt", format: :dotprompt)
    #
    # @example Registering a custom parser
    #   ParserRegistry.register(:custom, MyCustomParser)
    #
    class ParserRegistry
      class << self
        # Registered parsers by format
        #
        # @return [Hash{Symbol => Class}]
        def parsers
          @parsers ||= {}
        end

        # Register a parser for a format
        #
        # @param format [Symbol] Format identifier
        # @param parser_class [Class] Parser class (must respond to .parse and .parse_string)
        def register(format, parser_class)
          parsers[format.to_sym] = parser_class
        end

        # Get parser for a format
        #
        # @param format [Symbol] Format identifier
        # @return [Class] Parser class
        # @raise [UnknownFormatError] if no parser is registered
        def parser_for(format)
          parsers[format.to_sym] || raise(UnknownFormatError, "No parser registered for format: #{format}")
        end

        # Detect format from file path
        #
        # @param path [String] File path
        # @return [Symbol] Detected format
        # @raise [UnknownFormatError] if format cannot be detected
        def detect_format(path)
          extension = File.extname(path).downcase

          case extension
          when ".md"
            detect_markdown_format(path)
          when ".prompt"
            :dotprompt
          when ".yaml", ".yml"
            detect_yaml_format(path)
          when ".json"
            detect_json_format(path)
          else
            raise UnknownFormatError, "Cannot detect format for extension: #{extension}"
          end
        end

        # Parse a file, auto-detecting format if not specified
        #
        # @param path [String] Path to the file
        # @param format [Symbol, nil] Optional format override
        # @return [Manifest] Parsed manifest
        def parse(path, format: nil)
          format ||= detect_format(path)
          parser_for(format).parse(path)
        end

        # Parse content string with explicit format
        #
        # @param content [String] File content
        # @param format [Symbol] Format identifier
        # @return [Manifest] Parsed manifest
        def parse_string(content, format:)
          parser_for(format).parse_string(content)
        end

        # List all registered formats
        #
        # @return [Array<Symbol>]
        def registered_formats
          parsers.keys
        end

        # Alias for registered_formats
        # @return [Array<Symbol>]
        def formats
          registered_formats
        end

        # Check if a format is supported
        #
        # @param format [Symbol] Format to check
        # @return [Boolean]
        def format_supported?(format)
          parsers.key?(format.to_sym)
        end

        # Alias for format_supported?
        # @return [Boolean]
        def supports?(format)
          format_supported?(format)
        end

        private

        # Detect specific markdown format (agent.md vs prompt.md)
        def detect_markdown_format(path)
          basename = File.basename(path)

          if basename.end_with?(".agent.md")
            :agent_md
          elsif basename.end_with?(".prompt.md")
            :github_prompt
          else
            # Could be either - try to detect from content
            detect_markdown_format_from_content(path)
          end
        end

        # Detect markdown format from file content
        def detect_markdown_format_from_content(path)
          return :agent_md unless File.exist?(path)

          content = File.read(path, encoding: "UTF-8")

          # Look for distinctive markers in frontmatter
          if content.match?(/^---\s*\n.*?^activeagent:/m)
            :agent_md
          elsif content.match?(/^---\s*\n.*?^agent:/m)
            :github_prompt
          else
            # Default to agent_md for generic markdown with frontmatter
            :agent_md
          end
        rescue
          :agent_md
        end

        # Detect YAML format (CrewAI vs other)
        def detect_yaml_format(path)
          return :crewai unless File.exist?(path)

          content = File.read(path, encoding: "UTF-8")

          # CrewAI typically has role/goal/backstory pattern
          if content.match?(/role:\s*[>\|]?\s*\n?\s*.+/i) &&
             content.match?(/goal:\s*[>\|]?\s*\n?\s*.+/i)
            :crewai
          elsif content.match?(/has_context|activeagent/i)
            :activeagent_yaml
          else
            :yaml
          end
        rescue
          :yaml
        end

        # Detect JSON format
        def detect_json_format(path)
          return :json unless File.exist?(path)

          content = File.read(path, encoding: "UTF-8")
          data = JSON.parse(content)

          if data["inputSchema"]
            :mcp_tool
          elsif data["main"] && data["files"]
            :agent_package
          else
            :json
          end
        rescue
          :json
        end
      end
    end
  end
end

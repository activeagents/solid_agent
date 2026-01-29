# Agent Parser Design

A modular parser architecture that supports multiple agent definition formats with a unified internal representation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AgentManifest                                │
│                    (Unified Internal Model)                          │
└─────────────────────────────────────────────────────────────────────┘
                                 ▲
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         │                       │                       │
┌────────┴────────┐   ┌─────────┴─────────┐   ┌────────┴────────┐
│  AgentMdParser  │   │  DotpromptParser  │   │  CrewAIParser   │
│  (.agent.md)    │   │  (.prompt)        │   │  (agents.yaml)  │
└─────────────────┘   └───────────────────┘   └─────────────────┘
         │                       │                       │
         │                       │                       │
┌────────┴────────┐   ┌─────────┴─────────┐   ┌────────┴────────┐
│   Format A      │   │    Format B       │   │   Format C      │
│   .agent.md     │   │    .prompt        │   │   agents.yaml   │
└─────────────────┘   └───────────────────┘   └─────────────────┘

                                 │
                                 ▼
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌────────┴────────┐   ┌─────────┴─────────┐   ┌────────┴────────┐
│ ActiveAgent     │   │  CrewAI           │   │  LangChain      │
│ Exporter        │   │  Exporter         │   │  Exporter       │
└─────────────────┘   └───────────────────┘   └─────────────────┘
```

## Core Components

### 1. AgentManifest (Unified Model)

The canonical internal representation that all parsers produce and exporters consume:

```ruby
# lib/agent_manifest/manifest.rb
module AgentManifest
  class Manifest
    attr_accessor :name, :version, :description, :author, :license,
                  :repository, :tags, :extends

    attr_accessor :model, :config

    attr_accessor :input_schema, :output_schema

    attr_accessor :tools, :resources

    attr_accessor :instructions, :template

    attr_accessor :extensions  # Framework-specific: { activeagent: {}, crewai: {} }

    attr_accessor :examples, :tests

    attr_accessor :source_format, :source_path  # For round-trip preservation

    def initialize(attributes = {})
      attributes.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      @extensions ||= {}
      @tools ||= []
      @resources ||= []
      @tags ||= []
      @examples ||= []
      @tests ||= []
    end

    def to_h
      {
        name: name,
        version: version,
        description: description,
        author: author,
        license: license,
        repository: repository,
        tags: tags,
        extends: extends,
        model: model,
        config: config,
        input_schema: input_schema,
        output_schema: output_schema,
        tools: tools.map(&:to_h),
        resources: resources.map(&:to_h),
        instructions: instructions,
        template: template,
        extensions: extensions
      }.compact
    end

    # Convenience accessors for framework extensions
    def activeagent_config
      extensions[:activeagent] || {}
    end

    def crewai_config
      extensions[:crewai] || {}
    end

    def langchain_config
      extensions[:langchain] || {}
    end
  end

  class Tool
    attr_accessor :name, :description, :input_schema, :ref

    def initialize(attributes = {})
      attributes.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    end

    def reference?
      ref.present?
    end

    def to_h
      if reference?
        { "$ref" => ref }
      else
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }.compact
      end
    end

    # MCP-compatible JSON output
    def to_mcp_json
      {
        name: name,
        description: description,
        inputSchema: input_schema
      }.to_json
    end
  end

  class Resource
    attr_accessor :name, :description, :uri, :mime_type

    def initialize(attributes = {})
      attributes.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
    end

    def to_h
      {
        name: name,
        description: description,
        uri: uri,
        mimeType: mime_type
      }.compact
    end
  end

  class InputSchema
    attr_accessor :schema, :format  # format: :picoschema or :json_schema

    def initialize(schema:, format: :picoschema)
      @schema = schema
      @format = format
    end

    def to_json_schema
      case format
      when :picoschema
        PicoschemaParser.to_json_schema(schema)
      when :json_schema
        schema
      end
    end

    def to_picoschema
      case format
      when :picoschema
        schema
      when :json_schema
        PicoschemaParser.from_json_schema(schema)
      end
    end
  end
end
```

### 2. Parser Registry

```ruby
# lib/agent_manifest/parser_registry.rb
module AgentManifest
  class ParserRegistry
    class << self
      def parsers
        @parsers ||= {}
      end

      def register(format, parser_class)
        parsers[format.to_sym] = parser_class
      end

      def parser_for(format)
        parsers[format.to_sym] || raise(UnknownFormatError, "No parser for format: #{format}")
      end

      def detect_format(path)
        extension = File.extname(path).downcase
        case extension
        when '.md'
          # Could be .agent.md or regular markdown
          path.end_with?('.agent.md') ? :agent_md : :markdown
        when '.prompt'
          :dotprompt
        when '.yaml', '.yml'
          detect_yaml_format(path)
        when '.json'
          detect_json_format(path)
        else
          raise UnknownFormatError, "Cannot detect format for: #{path}"
        end
      end

      def parse(path, format: nil)
        format ||= detect_format(path)
        parser_for(format).parse(path)
      end

      def parse_string(content, format:)
        parser_for(format).parse_string(content)
      end

      private

      def detect_yaml_format(path)
        content = File.read(path)
        if content.include?('role:') && content.include?('goal:')
          :crewai
        elsif content.include?('has_context') || content.include?('activeagent')
          :activeagent_yaml
        else
          :yaml
        end
      end

      def detect_json_format(path)
        content = JSON.parse(File.read(path))
        if content['inputSchema']
          :mcp_tool
        elsif content['main'] && content['files']
          :agent_package
        else
          :json
        end
      end
    end
  end

  class UnknownFormatError < StandardError; end
end
```

### 3. Base Parser

```ruby
# lib/agent_manifest/parsers/base_parser.rb
module AgentManifest
  module Parsers
    class BaseParser
      class << self
        def parse(path)
          content = File.read(path)
          manifest = parse_string(content)
          manifest.source_path = path
          manifest.source_format = format_name
          manifest
        end

        def parse_string(content)
          raise NotImplementedError, "Subclasses must implement parse_string"
        end

        def format_name
          raise NotImplementedError, "Subclasses must implement format_name"
        end

        protected

        def normalize_model(model_string)
          # Normalize model identifiers to provider/model format
          return nil unless model_string

          if model_string.include?('/')
            model_string
          elsif model_string.start_with?('gpt-')
            "openai/#{model_string}"
          elsif model_string.start_with?('claude-')
            "anthropic/#{model_string}"
          elsif model_string.start_with?('gemini-')
            "google/#{model_string}"
          else
            model_string
          end
        end

        def parse_tools(tools_data)
          return [] unless tools_data

          tools_data.map do |tool_data|
            if tool_data.is_a?(String)
              Tool.new(ref: tool_data)
            elsif tool_data['$ref']
              Tool.new(ref: tool_data['$ref'])
            else
              Tool.new(
                name: tool_data['name'],
                description: tool_data['description'],
                input_schema: tool_data['inputSchema'] || tool_data['input_schema']
              )
            end
          end
        end
      end
    end
  end
end
```

## Format Parsers

### 4. AgentMd Parser (.agent.md)

```ruby
# lib/agent_manifest/parsers/agent_md_parser.rb
require 'yaml'

module AgentManifest
  module Parsers
    class AgentMdParser < BaseParser
      FRONTMATTER_REGEX = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

      class << self
        def format_name
          :agent_md
        end

        def parse_string(content)
          frontmatter, body = extract_frontmatter(content)

          Manifest.new(
            # Meta
            name: frontmatter['name'],
            version: frontmatter['version'] || '1.0.0',
            description: frontmatter['description'],
            author: frontmatter['author'],
            license: frontmatter['license'],
            repository: frontmatter['repository'],
            tags: frontmatter['tags'] || [],
            extends: frontmatter['extends'],

            # Model
            model: normalize_model(frontmatter['model']),
            config: frontmatter['config'] || {},

            # Schemas
            input_schema: parse_schema(frontmatter['input']),
            output_schema: parse_schema(frontmatter['output']),

            # Tools & Resources
            tools: parse_tools(frontmatter['tools']),
            resources: parse_resources(frontmatter['resources']),

            # Instructions
            instructions: extract_instructions(body),
            template: body,

            # Extensions
            extensions: extract_extensions(frontmatter)
          )
        end

        private

        def extract_frontmatter(content)
          match = content.match(FRONTMATTER_REGEX)
          raise ParseError, "Invalid .agent.md format: missing frontmatter" unless match

          frontmatter = YAML.safe_load(match[1], permitted_classes: [Symbol])
          body = match[2].strip

          [frontmatter, body]
        end

        def parse_schema(schema_data)
          return nil unless schema_data

          schema = schema_data['schema']
          return nil unless schema

          # Detect if it's Picoschema or JSON Schema
          if schema.is_a?(Hash) && schema['type']
            InputSchema.new(schema: schema, format: :json_schema)
          else
            InputSchema.new(schema: schema, format: :picoschema)
          end
        end

        def parse_resources(resources_data)
          return [] unless resources_data

          resources_data.map do |res|
            Resource.new(
              name: res['name'],
              description: res['description'],
              uri: res['uri'],
              mime_type: res['mimeType']
            )
          end
        end

        def extract_instructions(body)
          # Extract content from ## Instructions section
          if body =~ /##\s*Instructions\s*\n(.*?)(?=\n##|\z)/mi
            $1.strip
          else
            # Use entire body as instructions if no section found
            body.gsub(/^#\s+.*\n/, '').strip
          end
        end

        def extract_extensions(frontmatter)
          extensions = {}
          %w[activeagent crewai langchain genkit].each do |framework|
            extensions[framework.to_sym] = frontmatter[framework] if frontmatter[framework]
          end
          extensions
        end
      end
    end

    # Register the parser
    ParserRegistry.register(:agent_md, AgentMdParser)
  end
end
```

### 5. Dotprompt Parser (.prompt)

```ruby
# lib/agent_manifest/parsers/dotprompt_parser.rb
module AgentManifest
  module Parsers
    class DotpromptParser < BaseParser
      FRONTMATTER_REGEX = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

      class << self
        def format_name
          :dotprompt
        end

        def parse_string(content)
          frontmatter, body = extract_frontmatter(content)

          # Extract name from filename if not in frontmatter
          name = frontmatter['name'] || 'unnamed-prompt'

          Manifest.new(
            name: name,
            version: frontmatter['version'] || '1.0.0',

            # Model - Dotprompt format
            model: normalize_model(frontmatter['model']),
            config: extract_config(frontmatter),

            # Schemas - Dotprompt uses input/output directly
            input_schema: parse_dotprompt_schema(frontmatter['input']),
            output_schema: parse_dotprompt_output(frontmatter['output']),

            # Tools
            tools: parse_tools(frontmatter['tools']),

            # Template
            instructions: body,
            template: body,

            # Store original format info
            extensions: {
              dotprompt: frontmatter.except('model', 'input', 'output', 'tools')
            }
          )
        end

        private

        def extract_frontmatter(content)
          match = content.match(FRONTMATTER_REGEX)
          raise ParseError, "Invalid .prompt format: missing frontmatter" unless match

          [YAML.safe_load(match[1]), match[2].strip]
        end

        def extract_config(frontmatter)
          config = {}
          config[:temperature] = frontmatter['temperature'] if frontmatter['temperature']
          config[:max_tokens] = frontmatter['maxOutputTokens'] if frontmatter['maxOutputTokens']
          config[:top_p] = frontmatter['topP'] if frontmatter['topP']
          config[:top_k] = frontmatter['topK'] if frontmatter['topK']
          config[:stop] = frontmatter['stopSequences'] if frontmatter['stopSequences']
          config
        end

        def parse_dotprompt_schema(input_data)
          return nil unless input_data

          schema = input_data['schema']
          return nil unless schema

          # Dotprompt uses Picoschema by default
          InputSchema.new(schema: schema, format: :picoschema)
        end

        def parse_dotprompt_output(output_data)
          return nil unless output_data

          {
            format: output_data['format'],
            schema: output_data['schema']
          }
        end
      end
    end

    ParserRegistry.register(:dotprompt, DotpromptParser)
  end
end
```

### 6. CrewAI Parser (agents.yaml)

```ruby
# lib/agent_manifest/parsers/crewai_parser.rb
module AgentManifest
  module Parsers
    class CrewAIParser < BaseParser
      class << self
        def format_name
          :crewai
        end

        def parse_string(content)
          data = YAML.safe_load(content)

          # CrewAI files contain multiple agents, return array
          agents = data.map do |agent_name, agent_data|
            parse_agent(agent_name, agent_data)
          end

          # If single agent, return it directly
          agents.size == 1 ? agents.first : agents
        end

        def parse_file_pair(agents_path, tasks_path = nil)
          agents_content = File.read(agents_path)
          agents = parse_string(agents_content)

          if tasks_path && File.exist?(tasks_path)
            tasks = YAML.safe_load(File.read(tasks_path))
            # Merge task info into agents
            # (simplified - real implementation would be more complex)
          end

          agents
        end

        private

        def parse_agent(name, data)
          Manifest.new(
            name: name.to_s.underscore.dasherize,
            description: data['goal'],

            model: normalize_model(data['llm']),

            # CrewAI doesn't have formal schemas
            input_schema: nil,
            output_schema: nil,

            # Map tools
            tools: parse_crewai_tools(data['tools']),

            # Instructions from role + backstory
            instructions: build_instructions(data),
            template: build_template(data),

            # Preserve CrewAI-specific config
            extensions: {
              crewai: {
                role: data['role'],
                goal: data['goal'],
                backstory: data['backstory'],
                verbose: data['verbose'],
                allow_delegation: data['allow_delegation'],
                max_iter: data['max_iter'],
                max_rpm: data['max_rpm']
              }.compact
            }
          )
        end

        def parse_crewai_tools(tools)
          return [] unless tools

          tools.map do |tool|
            if tool.is_a?(String)
              # Reference to a tool class
              Tool.new(ref: tool)
            else
              Tool.new(
                name: tool['name'],
                description: tool['description'],
                input_schema: tool['args_schema']
              )
            end
          end
        end

        def build_instructions(data)
          parts = []
          parts << "Role: #{data['role']}" if data['role']
          parts << "Goal: #{data['goal']}" if data['goal']
          parts << "\n#{data['backstory']}" if data['backstory']
          parts.join("\n")
        end

        def build_template(data)
          <<~TEMPLATE
            # #{data['role']}

            ## Goal
            #{data['goal']}

            ## Backstory
            #{data['backstory']}
          TEMPLATE
        end
      end
    end

    ParserRegistry.register(:crewai, CrewAIParser)
  end
end
```

### 7. GitHub Prompt Parser (.prompt.md)

```ruby
# lib/agent_manifest/parsers/github_prompt_parser.rb
module AgentManifest
  module Parsers
    class GitHubPromptParser < BaseParser
      FRONTMATTER_REGEX = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

      class << self
        def format_name
          :github_prompt
        end

        def parse_string(content)
          frontmatter, body = extract_frontmatter(content)

          Manifest.new(
            name: extract_name_from_frontmatter(frontmatter),
            description: frontmatter['description'],

            model: normalize_model(frontmatter['model']),

            tools: parse_github_tools(frontmatter['tools']),

            instructions: body,
            template: body,

            extensions: {
              github_prompt: {
                agent: frontmatter['agent'],
                mode: frontmatter['mode']
              }.compact
            }
          )
        end

        private

        def extract_frontmatter(content)
          match = content.match(FRONTMATTER_REGEX)
          if match
            [YAML.safe_load(match[1]), match[2].strip]
          else
            [{}, content.strip]
          end
        end

        def extract_name_from_frontmatter(frontmatter)
          frontmatter['name'] || 'github-prompt'
        end

        def parse_github_tools(tools)
          return [] unless tools

          # GitHub tools are string references like 'githubRepo', 'search/codebase'
          tools.map do |tool|
            Tool.new(ref: "github://#{tool}")
          end
        end
      end
    end

    ParserRegistry.register(:github_prompt, GitHubPromptParser)
  end
end
```

## Format Exporters

### 8. Exporter Registry

```ruby
# lib/agent_manifest/exporter_registry.rb
module AgentManifest
  class ExporterRegistry
    class << self
      def exporters
        @exporters ||= {}
      end

      def register(format, exporter_class)
        exporters[format.to_sym] = exporter_class
      end

      def exporter_for(format)
        exporters[format.to_sym] || raise(UnknownFormatError, "No exporter for format: #{format}")
      end

      def export(manifest, format:, path: nil)
        content = exporter_for(format).export(manifest)
        if path
          File.write(path, content)
          path
        else
          content
        end
      end
    end
  end
end
```

### 9. AgentMd Exporter

```ruby
# lib/agent_manifest/exporters/agent_md_exporter.rb
module AgentManifest
  module Exporters
    class AgentMdExporter
      class << self
        def export(manifest)
          frontmatter = build_frontmatter(manifest)
          body = manifest.template || build_default_body(manifest)

          <<~OUTPUT
            ---
            #{frontmatter.to_yaml.lines[1..].join}---

            #{body}
          OUTPUT
        end

        private

        def build_frontmatter(manifest)
          fm = {}

          # Meta
          fm['name'] = manifest.name
          fm['version'] = manifest.version if manifest.version != '1.0.0'
          fm['description'] = manifest.description if manifest.description
          fm['author'] = manifest.author if manifest.author
          fm['license'] = manifest.license if manifest.license
          fm['repository'] = manifest.repository if manifest.repository
          fm['tags'] = manifest.tags if manifest.tags.any?
          fm['extends'] = manifest.extends if manifest.extends

          # Model
          fm['model'] = manifest.model if manifest.model
          fm['config'] = manifest.config if manifest.config&.any?

          # Schemas
          if manifest.input_schema
            fm['input'] = { 'schema' => manifest.input_schema.to_picoschema }
          end
          if manifest.output_schema
            fm['output'] = manifest.output_schema
          end

          # Tools
          if manifest.tools.any?
            fm['tools'] = manifest.tools.map(&:to_h)
          end

          # Resources
          if manifest.resources.any?
            fm['resources'] = manifest.resources.map(&:to_h)
          end

          # Extensions
          manifest.extensions.each do |framework, config|
            fm[framework.to_s] = config if config.any?
          end

          fm
        end

        def build_default_body(manifest)
          <<~BODY
            # #{manifest.name.titleize}

            #{manifest.description}

            ## Instructions

            #{manifest.instructions}
          BODY
        end
      end
    end

    ExporterRegistry.register(:agent_md, AgentMdExporter)
  end
end
```

### 10. Dotprompt Exporter

```ruby
# lib/agent_manifest/exporters/dotprompt_exporter.rb
module AgentManifest
  module Exporters
    class DotpromptExporter
      class << self
        def export(manifest)
          frontmatter = build_frontmatter(manifest)
          body = convert_template(manifest.template)

          <<~OUTPUT
            ---
            #{frontmatter.to_yaml.lines[1..].join}---

            #{body}
          OUTPUT
        end

        private

        def build_frontmatter(manifest)
          fm = {}

          fm['model'] = manifest.model if manifest.model

          # Config uses Dotprompt field names
          if manifest.config
            fm['temperature'] = manifest.config[:temperature] if manifest.config[:temperature]
            fm['maxOutputTokens'] = manifest.config[:max_tokens] if manifest.config[:max_tokens]
            fm['topP'] = manifest.config[:top_p] if manifest.config[:top_p]
            fm['topK'] = manifest.config[:top_k] if manifest.config[:top_k]
            fm['stopSequences'] = manifest.config[:stop] if manifest.config[:stop]
          end

          # Schemas
          if manifest.input_schema
            fm['input'] = { 'schema' => manifest.input_schema.to_picoschema }
          end
          if manifest.output_schema
            fm['output'] = manifest.output_schema
          end

          # Tools
          if manifest.tools.any?
            fm['tools'] = manifest.tools.map { |t| t.name }
          end

          fm
        end

        def convert_template(template)
          # Template syntax is compatible (both use Handlebars)
          # But may need to strip markdown sections
          return '' unless template

          # Remove markdown headers that aren't part of the prompt
          template
            .gsub(/^#\s+.*\n/, '')
            .gsub(/^##\s+(Instructions|Guidelines|Context)\s*\n/, '')
            .strip
        end
      end
    end

    ExporterRegistry.register(:dotprompt, DotpromptExporter)
  end
end
```

### 11. CrewAI Exporter

```ruby
# lib/agent_manifest/exporters/crewai_exporter.rb
module AgentManifest
  module Exporters
    class CrewAIExporter
      class << self
        def export(manifest)
          agent_key = manifest.name.underscore

          agent_data = build_agent_data(manifest)

          { agent_key => agent_data }.to_yaml
        end

        def export_multiple(manifests)
          agents = {}
          manifests.each do |manifest|
            agent_key = manifest.name.underscore
            agents[agent_key] = build_agent_data(manifest)
          end
          agents.to_yaml
        end

        private

        def build_agent_data(manifest)
          data = {}

          # Use CrewAI extension if available
          crewai = manifest.crewai_config

          data['role'] = crewai[:role] || extract_role(manifest)
          data['goal'] = crewai[:goal] || manifest.description
          data['backstory'] = crewai[:backstory] || manifest.instructions

          # Model
          data['llm'] = convert_model(manifest.model) if manifest.model

          # Tools
          if manifest.tools.any?
            data['tools'] = manifest.tools.map { |t| t.ref || t.name }
          end

          # Other CrewAI options
          data['verbose'] = crewai[:verbose] if crewai[:verbose]
          data['allow_delegation'] = crewai[:allow_delegation] if crewai.key?(:allow_delegation)
          data['max_iter'] = crewai[:max_iter] if crewai[:max_iter]
          data['max_rpm'] = crewai[:max_rpm] if crewai[:max_rpm]

          data.compact
        end

        def extract_role(manifest)
          # Try to extract role from instructions or name
          manifest.name.titleize.gsub('-', ' ')
        end

        def convert_model(model)
          # CrewAI uses different model format
          # e.g., "anthropic/claude-sonnet-4-20250514" -> "claude-sonnet-4-20250514" or provider-specific
          model.split('/').last
        end
      end
    end

    ExporterRegistry.register(:crewai, CrewAIExporter)
  end
end
```

## Picoschema Parser

```ruby
# lib/agent_manifest/picoschema_parser.rb
module AgentManifest
  class PicoschemaParser
    SCALAR_TYPES = %w[string integer number boolean any].freeze

    class << self
      # Convert Picoschema to JSON Schema
      def to_json_schema(picoschema)
        return nil unless picoschema

        if picoschema.is_a?(Hash)
          parse_object(picoschema)
        else
          { "type" => "object" }
        end
      end

      # Convert JSON Schema to Picoschema
      def from_json_schema(json_schema)
        return nil unless json_schema

        if json_schema['type'] == 'object' && json_schema['properties']
          convert_properties(json_schema['properties'], json_schema['required'] || [])
        else
          json_schema
        end
      end

      private

      def parse_object(schema_hash)
        properties = {}
        required = []

        schema_hash.each do |key, value|
          field_name, optional = parse_field_name(key)
          field_schema = parse_field(value)

          properties[field_name] = field_schema
          required << field_name unless optional
        end

        result = { "type" => "object", "properties" => properties }
        result["required"] = required if required.any?
        result
      end

      def parse_field_name(key)
        if key.end_with?('?')
          [key.chomp('?'), true]  # optional
        else
          [key, false]  # required
        end
      end

      def parse_field(value)
        case value
        when String
          parse_type_string(value)
        when Hash
          # Nested object
          parse_object(value)
        when Array
          # Array type
          if value.first.is_a?(Hash)
            { "type" => "array", "items" => parse_object(value.first) }
          else
            { "type" => "array", "items" => parse_type_string(value.first.to_s) }
          end
        else
          { "type" => "string" }
        end
      end

      def parse_type_string(type_str)
        # Parse: "type, description" or "type(enum1, enum2), description"
        parts = type_str.split(',', 2)
        type_part = parts[0].strip
        description = parts[1]&.strip

        result = {}

        # Check for enum: string(a, b, c)
        if type_part =~ /^(\w+)\(([^)]+)\)$/
          base_type = $1
          enum_values = $2.split(',').map(&:strip)
          result["type"] = base_type
          result["enum"] = enum_values
        elsif SCALAR_TYPES.include?(type_part)
          result["type"] = type_part
        elsif type_part.start_with?('[') && type_part.end_with?(']')
          inner = type_part[1..-2]
          result["type"] = "array"
          result["items"] = { "type" => inner }
        else
          result["type"] = type_part
        end

        result["description"] = description if description

        result
      end

      def convert_properties(properties, required_fields)
        result = {}

        properties.each do |name, schema|
          optional = !required_fields.include?(name)
          key = optional ? "#{name}?" : name
          result[key] = convert_schema_to_pico(schema)
        end

        result
      end

      def convert_schema_to_pico(schema)
        type = schema['type']
        desc = schema['description']

        pico = type.to_s
        if schema['enum']
          pico = "#{type}(#{schema['enum'].join(', ')})"
        end
        if desc
          pico = "#{pico}, #{desc}"
        end

        pico
      end
    end
  end
end
```

## Main Entry Point

```ruby
# lib/agent_manifest.rb
require_relative 'agent_manifest/manifest'
require_relative 'agent_manifest/parser_registry'
require_relative 'agent_manifest/exporter_registry'
require_relative 'agent_manifest/picoschema_parser'

# Load all parsers
require_relative 'agent_manifest/parsers/base_parser'
require_relative 'agent_manifest/parsers/agent_md_parser'
require_relative 'agent_manifest/parsers/dotprompt_parser'
require_relative 'agent_manifest/parsers/crewai_parser'
require_relative 'agent_manifest/parsers/github_prompt_parser'

# Load all exporters
require_relative 'agent_manifest/exporters/agent_md_exporter'
require_relative 'agent_manifest/exporters/dotprompt_exporter'
require_relative 'agent_manifest/exporters/crewai_exporter'

module AgentManifest
  class << self
    # Parse any supported format
    def parse(path, format: nil)
      ParserRegistry.parse(path, format: format)
    end

    # Parse from string
    def parse_string(content, format:)
      ParserRegistry.parse_string(content, format: format)
    end

    # Export to any supported format
    def export(manifest, format:, path: nil)
      ExporterRegistry.export(manifest, format: format, path: path)
    end

    # Convert between formats
    def convert(input_path, output_format:, output_path: nil)
      manifest = parse(input_path)
      export(manifest, format: output_format, path: output_path)
    end

    # Load and instantiate as ActiveAgent
    def load_agent(path, format: nil)
      manifest = parse(path, format: format)
      AgentBuilder.build(manifest)
    end
  end
end
```

## ActiveAgent Integration

```ruby
# lib/agent_manifest/agent_builder.rb
module AgentManifest
  class AgentBuilder
    class << self
      def build(manifest)
        # Create a dynamic agent class from manifest
        agent_class = Class.new(base_class(manifest)) do
          # Include concerns based on manifest
        end

        # Configure from manifest
        configure_agent(agent_class, manifest)

        agent_class
      end

      private

      def base_class(manifest)
        config = manifest.activeagent_config
        parent = config[:parent_class] || 'ApplicationAgent'
        parent.constantize
      rescue NameError
        ActiveAgent::Base
      end

      def configure_agent(klass, manifest)
        config = manifest.activeagent_config

        # Set model
        if manifest.model
          provider, model = manifest.model.split('/')
          klass.generate_with provider.to_sym, model: model
        end

        # Include concerns
        concerns = config[:concerns] || []
        concerns.each do |concern|
          apply_concern(klass, concern)
        end

        # Define tools
        manifest.tools.each do |tool|
          define_tool(klass, tool) unless tool.reference?
        end

        # Set instructions
        klass.define_method(:system_instructions) do
          manifest.instructions
        end
      end

      def apply_concern(klass, concern)
        case concern
        when Hash
          concern.each do |name, options|
            case name.to_sym
            when :has_context
              klass.include(SolidAgent::HasContext)
              klass.has_context(**options.symbolize_keys)
            when :has_tools
              klass.include(SolidAgent::HasTools)
              klass.has_tools(*options) if options.is_a?(Array)
            when :streams_tool_updates
              klass.include(SolidAgent::StreamsToolUpdates)
            end
          end
        when String, Symbol
          klass.include("SolidAgent::#{concern.to_s.camelize}".constantize)
        end
      end

      def define_tool(klass, tool)
        klass.tool tool.name.to_sym do
          description tool.description
          if tool.input_schema && tool.input_schema['properties']
            tool.input_schema['properties'].each do |param_name, param_schema|
              required = tool.input_schema['required']&.include?(param_name)
              parameter param_name.to_sym,
                type: param_schema['type']&.to_sym,
                required: required,
                description: param_schema['description']
            end
          end
        end
      end
    end
  end
end
```

## CLI Commands

```ruby
# lib/agent_manifest/cli.rb
module AgentManifest
  class CLI < Thor
    desc "parse PATH", "Parse an agent file and display info"
    option :format, type: :string, desc: "Force input format"
    option :json, type: :boolean, desc: "Output as JSON"
    def parse(path)
      manifest = AgentManifest.parse(path, format: options[:format]&.to_sym)

      if options[:json]
        puts JSON.pretty_generate(manifest.to_h)
      else
        display_manifest(manifest)
      end
    end

    desc "convert INPUT OUTPUT", "Convert between agent formats"
    option :from, type: :string, desc: "Input format"
    option :to, type: :string, required: true, desc: "Output format"
    def convert(input, output)
      manifest = AgentManifest.parse(input, format: options[:from]&.to_sym)
      AgentManifest.export(manifest, format: options[:to].to_sym, path: output)
      say "Converted #{input} -> #{output}", :green
    end

    desc "validate PATH", "Validate an agent file"
    def validate(path)
      manifest = AgentManifest.parse(path)
      errors = Validator.validate(manifest)

      if errors.empty?
        say "✓ Valid agent definition", :green
      else
        say "✗ Validation errors:", :red
        errors.each { |e| say "  - #{e}", :red }
        exit 1
      end
    end

    desc "init NAME", "Create a new agent file"
    option :format, type: :string, default: "agent_md", desc: "Output format"
    option :template, type: :string, desc: "Template to use"
    def init(name)
      # Generate from template
    end

    private

    def display_manifest(manifest)
      say "Agent: #{manifest.name}", :green
      say "Version: #{manifest.version}"
      say "Model: #{manifest.model}" if manifest.model
      say "Tools: #{manifest.tools.map(&:name).join(', ')}" if manifest.tools.any?
      say "Description: #{manifest.description}" if manifest.description
    end
  end
end
```

## Usage Examples

```ruby
# Parse any format
manifest = AgentManifest.parse("research-assistant.agent.md")
manifest = AgentManifest.parse("agent.prompt")  # Dotprompt
manifest = AgentManifest.parse("agents.yaml")   # CrewAI

# Convert formats
AgentManifest.convert("agent.prompt", output_format: :agent_md, output_path: "agent.agent.md")
AgentManifest.convert("agents.yaml", output_format: :agent_md, output_path: "agent.agent.md")

# Export to different format
content = AgentManifest.export(manifest, format: :crewai)
AgentManifest.export(manifest, format: :dotprompt, path: "output.prompt")

# Load and use as ActiveAgent
agent_class = AgentManifest.load_agent("research-assistant.agent.md")
agent = agent_class.new(params: { query: "What is AI?" })
result = agent.research.generate_now

# Parse from string
content = File.read("agent.agent.md")
manifest = AgentManifest.parse_string(content, format: :agent_md)
```

## Supported Formats Summary

| Format | Extension | Parse | Export | Notes |
|--------|-----------|-------|--------|-------|
| AgentMd | `.agent.md` | ✅ | ✅ | Native format |
| Dotprompt | `.prompt` | ✅ | ✅ | Google/Firebase |
| CrewAI | `agents.yaml` | ✅ | ✅ | Python framework |
| GitHub Prompt | `.prompt.md` | ✅ | ⚠️ | Copilot prompts |
| LangChain | `*.py` | 🚧 | 🚧 | Code-based |
| MCP Tool | `.tool.json` | ✅ | ✅ | Tool definitions only |

✅ Full support | ⚠️ Partial | 🚧 Planned

# frozen_string_literal: true

require "yaml"

module ActivePrompt
  # AgentLoader loads agent definitions from various YAML and Markdown formats.
  #
  # Supports:
  # - .agent.md (SolidAgent native format)
  # - agents.yaml (CrewAI-compatible format)
  # - Individual YAML tool definitions
  #
  # @example Loading an agent from manifest
  #   loader = ActivePrompt::AgentLoader.new
  #   agent_class = loader.load_agent("config/agents/github-trends.agent.md")
  #   agent = agent_class.new(language: "ruby")
  #
  # @example Loading from CrewAI agents.yaml
  #   loader = ActivePrompt::AgentLoader.new
  #   agents = loader.load_crew_agents("config/agents/agents.yaml")
  #
  class AgentLoader
    MANIFEST_EXTENSIONS = %w[.agent.md .prompt .prompt.md].freeze
    YAML_EXTENSIONS = %w[.yaml .yml].freeze

    attr_reader :config_path, :tool_definitions

    def initialize(config_path: nil)
      @config_path = config_path || default_config_path
      @tool_definitions = {}
      @loaded_agents = {}
    end

    # Load an agent from a manifest file
    #
    # @param path [String] Path to manifest file
    # @param base_class [Class, nil] Optional base class
    # @return [Class] Agent class
    def load_agent(path, base_class: nil)
      return @loaded_agents[path] if @loaded_agents[path]

      full_path = resolve_path(path)
      raise ConfigurationError, "Agent manifest not found: #{path}" unless File.exist?(full_path)

      manifest = parse_manifest(full_path)
      agent_class = build_agent_class(manifest, base_class: base_class)

      # Register with ActivePrompt
      register_agent_prompt(manifest)

      @loaded_agents[path] = agent_class
    end

    # Load all agents from a CrewAI-style agents.yaml
    #
    # @param path [String] Path to agents.yaml
    # @return [Hash<String, Class>] Map of agent names to classes
    def load_crew_agents(path)
      full_path = resolve_path(path)
      data = YAML.safe_load(File.read(full_path), permitted_classes: [Symbol])

      agents = {}

      data["agents"]&.each do |name, config|
        manifest = crew_config_to_manifest(name, config)
        agent_class = build_agent_class(manifest)
        register_agent_prompt(manifest)
        agents[name] = agent_class
      end

      # Also load tool definitions
      load_tool_definitions(data["tools"]) if data["tools"]

      agents
    end

    # Load tool definitions from YAML
    #
    # @param path [String] Path to tools YAML file
    # @return [Hash] Tool definitions
    def load_tools(path)
      full_path = resolve_path(path)
      data = YAML.safe_load(File.read(full_path), permitted_classes: [Symbol])

      load_tool_definitions(data["tools"]) if data["tools"]

      @tool_definitions
    end

    # Load MCP configuration
    #
    # @param path [String] Path to MCP YAML file
    # @return [Hash] MCP configuration
    def load_mcp_config(path)
      full_path = resolve_path(path)
      data = YAML.safe_load(File.read(full_path), permitted_classes: [Symbol])

      {
        name: data["name"],
        version: data["version"],
        description: data["description"],
        transport: data["transport"],
        server: data["server"],
        tools: data["tools"],
        resources: data["resources"],
        prompts: data["prompts"]
      }
    end

    # Load CLI configuration
    #
    # @param path [String] Path to CLI YAML file
    # @return [Hash] CLI configuration
    def load_cli_config(path)
      full_path = resolve_path(path)
      data = YAML.safe_load(File.read(full_path), permitted_classes: [Symbol])

      {
        version: data["version"],
        name: data["name"],
        defaults: data["defaults"],
        agents: data["agents"],
        mcp: data["mcp"],
        sessions: data["sessions"],
        auth: data["auth"],
        output: data["output"],
        logging: data["logging"],
        commands: data["commands"],
        aliases: data["aliases"]
      }
    end

    # Get tool definition by name
    #
    # @param name [String] Tool name
    # @return [Hash, nil] Tool definition
    def get_tool(name)
      @tool_definitions[name.to_s]
    end

    # Get tools for a preset
    #
    # @param preset_name [String] Preset name
    # @param tools_config [Hash] Tools configuration with presets
    # @return [Array<Hash>] Array of tool definitions
    def get_preset_tools(preset_name, tools_config)
      preset = tools_config.dig("presets", preset_name)
      return [] unless preset

      if preset["tools"] == "all"
        @tool_definitions.values
      else
        preset["tools"].map { |name| get_tool(name) }.compact
      end
    end

    private

    def default_config_path
      if defined?(Rails)
        Rails.root.join("config", "agents")
      else
        File.expand_path("../../config/agents", __dir__)
      end
    end

    def resolve_path(path)
      return path if File.absolute_path?(path) == path

      File.join(@config_path, path)
    end

    def parse_manifest(path)
      extension = File.extname(path)

      if extension == ".md" || path.end_with?(".agent.md")
        parse_agent_md(path)
      elsif YAML_EXTENSIONS.include?(extension)
        parse_yaml_manifest(path)
      else
        raise ConfigurationError, "Unknown manifest format: #{extension}"
      end
    end

    def parse_agent_md(path)
      content = File.read(path)

      # Extract YAML frontmatter
      if content =~ /\A---\n(.+?)\n---\n(.*)/m
        frontmatter = YAML.safe_load($1, permitted_classes: [Symbol])
        body = $2.strip

        frontmatter.merge(
          "instructions" => extract_instructions(body),
          "template" => body,
          "source_format" => :agent_md,
          "source_path" => path
        )
      else
        raise ConfigurationError, "Invalid .agent.md format: missing frontmatter"
      end
    end

    def parse_yaml_manifest(path)
      YAML.safe_load(File.read(path), permitted_classes: [Symbol])
    end

    def extract_instructions(body)
      # Extract main instructions, excluding task template section
      lines = body.lines
      instructions_lines = []
      in_task_section = false

      lines.each do |line|
        if line =~ /^##\s*Task/i
          in_task_section = true
        elsif line =~ /^##\s/ && in_task_section
          in_task_section = false
        end

        instructions_lines << line unless in_task_section
      end

      instructions_lines.join.strip
    end

    def crew_config_to_manifest(name, config)
      activeagent = config["activeagent"] || {}

      {
        "name" => name.to_s.tr("_", "-"),
        "version" => "1.0.0",
        "description" => config["goal"],
        "model" => activeagent["model"] || ActivePrompt.configuration.default_model,
        "config" => activeagent["config"] || {},
        "instructions" => build_crew_instructions(config),
        "tools" => config["tools"]&.map { |t| { "name" => t } } || [],
        "extensions" => {
          "activeagent" => activeagent,
          "crewai" => {
            "role" => config["role"],
            "goal" => config["goal"],
            "backstory" => config["backstory"],
            "verbose" => config["verbose"],
            "allow_delegation" => config["allow_delegation"]
          }
        }
      }
    end

    def build_crew_instructions(config)
      <<~INSTRUCTIONS
        # Role
        #{config['role']}

        # Goal
        #{config['goal']}

        # Background
        #{config['backstory']}
      INSTRUCTIONS
    end

    def build_agent_class(manifest, base_class: nil)
      base = base_class || determine_base_class(manifest)

      Class.new(base) do
        # Include required concerns
        include ActivePrompt::BrowserAgent if manifest["tools"]&.any? { |t| t["name"]&.start_with?("browser_") }

        # Set class-level configuration
        define_singleton_method(:manifest) { manifest }
        define_singleton_method(:agent_name) { manifest["name"] }
        define_singleton_method(:agent_version) { manifest["version"] }

        # Initialize with manifest configuration
        define_method(:initialize) do |params = {}|
          @manifest = manifest
          @task_instructions = manifest["instructions"]
          super(params)
        end

        # Override prompt options
        define_method(:default_prompt_options) do
          {
            model: manifest["model"],
            instructions: manifest["instructions"],
            **manifest["config"]
          }
        end

        # Get tools from manifest
        define_method(:manifest_tools) do
          manifest["tools"]&.map do |tool|
            if tool.is_a?(Hash)
              {
                type: "function",
                function: {
                  name: tool["name"],
                  description: tool["description"],
                  parameters: tool["inputSchema"] || tool["input_schema"] || {}
                }
              }
            else
              { type: "function", function: { name: tool.to_s } }
            end
          end || []
        end
      end
    end

    def determine_base_class(manifest)
      activeagent_config = manifest.dig("extensions", "activeagent") ||
                          manifest.dig("activeagent") ||
                          {}

      class_name = activeagent_config["class_name"]

      if class_name && Object.const_defined?(class_name)
        Object.const_get(class_name)
      elsif defined?(ApplicationAgent)
        ApplicationAgent
      else
        Object
      end
    end

    def load_tool_definitions(tools)
      tools.each do |name, definition|
        @tool_definitions[name.to_s] = definition.merge("name" => name.to_s)
      end
    end

    def register_agent_prompt(manifest)
      # Create a Prompt record for the agent
      return unless defined?(ActivePrompt::Prompt) && ActivePrompt::Prompt.table_exists?

      ActivePrompt::Prompt.find_or_create_by!(
        name: manifest["name"],
        version: manifest["version"] || "1.0.0"
      ) do |prompt|
        prompt.model = manifest["model"] || ActivePrompt.configuration.default_model
        prompt.description = manifest["description"]
        prompt.instructions = manifest["instructions"]
        prompt.tools = manifest["tools"]
        prompt.config = manifest["config"]
        prompt.extensions = manifest["extensions"]
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[AgentLoader] Could not register prompt: #{e.message}") if defined?(Rails)
    end
  end
end

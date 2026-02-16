# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Parsers
      # CrewAIParser handles CrewAI's agents.yaml format.
      #
      # CrewAI defines agents with role, goal, and backstory.
      # This parser converts them to the unified Manifest format.
      #
      # @see https://docs.crewai.com
      #
      # @example agents.yaml
      #   research_analyst:
      #     role: >
      #       Senior Research Analyst
      #     goal: >
      #       Uncover cutting-edge developments
      #     backstory: >
      #       You're a seasoned researcher...
      #     llm: claude-sonnet-4-20250514
      #     tools:
      #       - SerperDevTool
      #
      class CrewAIParser < BaseParser
        class << self
          def format_name
            :crewai
          end

          def parse_string(content)
            data = YAML.safe_load(content, permitted_classes: [Symbol])

            raise ParseError, "Invalid CrewAI YAML: expected hash" unless data.is_a?(Hash)

            # CrewAI files can contain multiple agents
            agents = data.map do |agent_name, agent_data|
              parse_agent(agent_name.to_s, agent_data)
            end

            # If single agent, return it directly; otherwise return array
            agents.size == 1 ? agents.first : agents
          end

          # Parse a file containing multiple agents
          #
          # @param agents_path [String] Path to agents.yaml
          # @param tasks_path [String, nil] Optional path to tasks.yaml
          # @return [Array<Manifest>] Parsed manifests
          def parse_with_tasks(agents_path, tasks_path = nil)
            agents_content = File.read(agents_path, encoding: "UTF-8")
            result = parse_string(agents_content)

            # Ensure we have an array
            manifests = result.is_a?(Array) ? result : [result]

            # Optionally merge task information
            if tasks_path && File.exist?(tasks_path)
              tasks = YAML.safe_load(File.read(tasks_path, encoding: "UTF-8"))
              merge_tasks(manifests, tasks)
            end

            manifests
          end

          private

          def parse_agent(name, data)
            return nil unless data.is_a?(Hash)

            Manifest.new(
              # Convert snake_case name to kebab-case
              name: name.tr("_", "-"),
              description: clean_multiline(data["goal"]),

              # Model
              model: normalize_model(data["llm"]),
              config: parse_crewai_config(data),

              # Build instructions from role + backstory
              instructions: build_instructions(data),
              template: build_template(data),

              # Tools (as references to Python classes)
              tools: parse_crewai_tools(data["tools"]),

              # Preserve CrewAI-specific config
              extensions: {
                crewai: build_crewai_extensions(data)
              }
            )
          end

          # Parse CrewAI config options
          def parse_crewai_config(data)
            config = {}

            # CrewAI doesn't have direct model config in YAML typically
            # but some implementations support it
            config[:temperature] = data["temperature"] if data["temperature"]
            config[:max_tokens] = data["max_tokens"] if data["max_tokens"]

            config.compact
          end

          # Build instructions from role and backstory
          def build_instructions(data)
            parts = []

            role = clean_multiline(data["role"])
            goal = clean_multiline(data["goal"])
            backstory = clean_multiline(data["backstory"])

            parts << "Role: #{role}" if role.present?
            parts << "Goal: #{goal}" if goal.present?
            parts << "\n#{backstory}" if backstory.present?

            parts.join("\n").strip
          end

          # Build a markdown template from CrewAI data
          def build_template(data)
            role = clean_multiline(data["role"]) || "Agent"
            goal = clean_multiline(data["goal"])
            backstory = clean_multiline(data["backstory"])

            template = "# #{role}\n\n"
            template += "## Goal\n\n#{goal}\n\n" if goal
            template += "## Backstory\n\n#{backstory}\n\n" if backstory
            template
          end

          # Parse CrewAI tool references
          def parse_crewai_tools(tools_data)
            return [] unless tools_data.is_a?(Array)

            tools_data.map do |tool|
              if tool.is_a?(String)
                # Reference to a Python tool class
                Tool.new(ref: "crewai://#{tool}")
              elsif tool.is_a?(Hash)
                Tool.from_hash(tool)
              else
                nil
              end
            end.compact
          end

          # Build CrewAI-specific extensions
          def build_crewai_extensions(data)
            {
              role: clean_multiline(data["role"]),
              goal: clean_multiline(data["goal"]),
              backstory: clean_multiline(data["backstory"]),
              verbose: data["verbose"],
              allow_delegation: data["allow_delegation"],
              max_iter: data["max_iter"],
              max_rpm: data["max_rpm"],
              memory: data["memory"],
              cache: data["cache"],
              step_callback: data["step_callback"],
              system_template: data["system_template"],
              prompt_template: data["prompt_template"],
              response_template: data["response_template"]
            }.compact
          end

          # Clean up YAML multiline strings
          def clean_multiline(value)
            return nil unless value
            value.to_s.strip.gsub(/\s+/, " ")
          end

          # Merge task information into manifests
          def merge_tasks(manifests, tasks)
            # Tasks in CrewAI are associated with agents
            # This is a simplified merge - full implementation would be more complex
            tasks.each do |task_name, task_data|
              agent_name = task_data["agent"]&.tr("_", "-")
              manifest = manifests.find { |m| m.name == agent_name }

              if manifest
                # Add task information to extensions
                manifest.extensions[:crewai] ||= {}
                manifest.extensions[:crewai][:tasks] ||= []
                manifest.extensions[:crewai][:tasks] << {
                  name: task_name,
                  description: task_data["description"],
                  expected_output: task_data["expected_output"]
                }
              end
            end
          end
        end
      end

      # Register the parser
      ParserRegistry.register(:crewai, CrewAIParser)
    end
  end
end

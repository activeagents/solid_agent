# frozen_string_literal: true

require "rails/generators"

module SolidAgent
  module Generators
    class ManifestGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generates a .agent.md manifest file for an agent"

      class_option :model, type: :string, default: "anthropic/claude-sonnet-4-20250514",
        desc: "Model identifier (provider/model format)"

      class_option :tools, type: :array, default: [],
        desc: "Tool names to include"

      class_option :template, type: :string, default: nil,
        desc: "Use a preset template (research, assistant, reviewer, chat)"

      class_option :format, type: :string, default: "agent_md",
        desc: "Output format (agent_md, dotprompt)"

      class_option :context, type: :string, default: nil,
        desc: "Contextual param key for HasContext (e.g., user, document)"

      class_option :description, type: :string, default: nil,
        desc: "Agent description"

      def create_manifest_file
        @model = options[:model]
        @tools = options[:tools]
        @preset = options[:template]
        @format = options[:format].to_sym
        @contextual = options[:context]
        @description = options[:description] || default_description

        # Apply preset template configuration
        apply_preset if @preset

        case @format
        when :agent_md
          template "agent.md.erb", manifest_path(".agent.md")
        when :dotprompt
          template "prompt.erb", manifest_path(".prompt")
        else
          template "agent.md.erb", manifest_path(".agent.md")
        end
      end

      def show_next_steps
        say ""
        say "Manifest created successfully!", :green
        say ""
        say "File generated:"
        say "  #{manifest_path(extension_for_format)}"
        say ""
        say "Usage:", :yellow
        say "  # Parse the manifest"
        say "  manifest = SolidAgent::AgentManifest.parse(\"#{manifest_path(extension_for_format)}\")"
        say ""
        say "  # Load as agent class"
        say "  klass = SolidAgent::AgentManifest.load_agent(\"#{manifest_path(extension_for_format)}\")"
        say ""
        say "  # Validate the manifest"
        say "  SolidAgent::AgentManifest.validate!(\"#{manifest_path(extension_for_format)}\")"
        say ""

        if @tools.any?
          say "Tool stubs added. Implement the tool methods in your agent class:", :yellow
          @tools.each do |tool|
            say "  def #{tool}(args)"
            say "    # Implement #{tool} logic"
            say "  end"
          end
          say ""
        end
      end

      private

      def file_name
        name.underscore
      end

      def class_name
        name.camelize
      end

      def agent_class_name
        "#{class_name}Agent"
      end

      def agent_title
        class_name.gsub(/([A-Z])/, ' \1').strip
      end

      def manifest_path(extension)
        "app/views/#{file_name}_agent/agent#{extension}"
      end

      def extension_for_format
        case @format
        when :agent_md then ".agent.md"
        when :dotprompt then ".prompt"
        else ".agent.md"
        end
      end

      def default_description
        "#{agent_title} agent"
      end

      def apply_preset
        case @preset.to_s
        when "research"
          @description ||= "Research and analyze topics thoroughly, providing well-sourced information"
          @tools = %w[search fetch analyze] if @tools.empty?
          @preset_instructions = research_instructions
        when "assistant"
          @description ||= "General-purpose assistant for answering questions and helping with tasks"
          @preset_instructions = assistant_instructions
        when "reviewer"
          @description ||= "Review and provide feedback on content, code, or documents"
          @tools = %w[read_file analyze_diff] if @tools.empty?
          @preset_instructions = reviewer_instructions
        when "chat"
          @description ||= "Conversational agent for multi-turn dialogue"
          @contextual ||= "user"
          @preset_instructions = chat_instructions
        end
      end

      def research_instructions
        <<~INSTRUCTIONS
          You are a thorough research assistant. Your goal is to provide accurate,
          well-sourced information on any topic.

          ## Guidelines

          - Always cite your sources when providing information
          - Present multiple perspectives when topics are controversial
          - Acknowledge uncertainty when information is incomplete
          - Break down complex topics into understandable explanations
          - Verify facts before presenting them
        INSTRUCTIONS
      end

      def assistant_instructions
        <<~INSTRUCTIONS
          You are a helpful assistant. Your goal is to assist users with their
          questions and tasks effectively.

          ## Guidelines

          - Be concise but thorough in your responses
          - Ask clarifying questions when requests are ambiguous
          - Provide step-by-step guidance for complex tasks
          - Offer alternatives when appropriate
        INSTRUCTIONS
      end

      def reviewer_instructions
        <<~INSTRUCTIONS
          You are a thorough reviewer. Your goal is to provide constructive feedback
          that helps improve the quality of the work.

          ## Guidelines

          - Focus on both strengths and areas for improvement
          - Be specific with your feedback
          - Provide actionable suggestions
          - Maintain a constructive and respectful tone
          - Consider the context and goals of the work
        INSTRUCTIONS
      end

      def chat_instructions
        <<~INSTRUCTIONS
          You are a conversational assistant. Engage in helpful, natural dialogue
          while maintaining context from previous messages.

          ## Guidelines

          - Remember context from earlier in the conversation
          - Ask follow-up questions to better understand the user's needs
          - Be friendly and approachable
          - Know when to be concise vs. detailed based on the question
        INSTRUCTIONS
      end

      def default_instructions
        @preset_instructions || <<~INSTRUCTIONS
          You are the #{agent_title} agent.

          ## Instructions

          TODO - Add your agent's instructions here.

          ## Guidelines

          - Be helpful and accurate
          - Follow the user's instructions carefully
          - Ask for clarification when needed
        INSTRUCTIONS
      end
    end
  end
end

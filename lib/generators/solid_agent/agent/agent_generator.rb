# frozen_string_literal: true

require "rails/generators"

module SolidAgent
  module Generators
    class AgentGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generates a new ActiveAgent agent with SolidAgent concerns"

      class_option :context, type: :boolean, default: true,
        desc: "Include HasContext concern"

      class_option :tools, type: :boolean, default: false,
        desc: "Include HasTools concern"

      class_option :streaming, type: :boolean, default: false,
        desc: "Include StreamsToolUpdates concern"

      class_option :actions, type: :array, default: ["perform"],
        desc: "Agent actions to generate"

      class_option :parent, type: :string, default: "ApplicationAgent",
        desc: "Parent class for the agent"

      def create_agent_file
        @parent_class = options[:parent]
        @include_context = options[:context]
        @include_tools = options[:tools]
        @include_streaming = options[:streaming]
        @actions = options[:actions]

        template "agent.rb.erb", "app/agents/#{file_name}_agent.rb"
      end

      def create_view_directory
        empty_directory "app/views/#{file_name}_agent"

        @actions.each do |action|
          template "action.text.erb", "app/views/#{file_name}_agent/#{action}.text.erb",
            action_name: action
        end
      end

      def create_tools_directory
        return unless @include_tools

        empty_directory "app/views/#{file_name}_agent/tools"
      end

      def show_next_steps
        say ""
        say "Agent created successfully!", :green
        say ""
        say "Files generated:"
        say "  app/agents/#{file_name}_agent.rb"
        say "  app/views/#{file_name}_agent/"
        @actions.each do |action|
          say "  app/views/#{file_name}_agent/#{action}.text.erb"
        end
        say "  app/views/#{file_name}_agent/tools/" if @include_tools
        say ""

        if @include_tools
          say "To add tools, run:", :yellow
          say "  rails g solid_agent:tool search #{class_name}Agent --parameters query:string:required --description \"Search for content\""
          say ""
        end

        say "Example usage:", :yellow
        say "  #{class_name}Agent.with(content: \"Hello\").#{@actions.first}.generate_now"
        say ""
      end

      private

      def file_name
        name.underscore
      end

      def class_name
        name.camelize
      end
    end
  end
end

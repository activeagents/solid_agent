# frozen_string_literal: true

require "rails/generators"

module SolidAgent
  module Generators
    class ToolGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generates a tool schema JSON template and optional tool method for an agent"

      argument :agent_name, type: :string, required: true,
        desc: "The agent class name (e.g., ResearchAgent)"

      class_option :parameters, type: :array, default: [],
        desc: "Tool parameters in name:type:required format (e.g., url:string:required query:string)"

      class_option :description, type: :string, default: "",
        desc: "Tool description"

      class_option :inline, type: :boolean, default: false,
        desc: "Generate inline tool definition instead of JSON template"

      def create_tool_template
        if options[:inline]
          say "Inline tool definition for #{agent_name}:", :green
          say ""
          say inline_tool_definition
          say ""
        else
          @tool_description = options[:description].presence || "#{name.humanize} tool"
          @parameters = parse_parameters

          template "tool.json.erb", tool_template_path
          say "Created tool template: #{tool_template_path}", :green
        end
      end

      def show_method_stub
        say ""
        say "Add this method to your #{agent_name}:", :yellow
        say ""
        say tool_method_stub
        say ""

        if options[:inline]
          say "Add this to your agent class:", :yellow
          say ""
          say inline_tool_definition
          say ""
        else
          say "Don't forget to register the tool in your agent:", :yellow
          say ""
          say "  has_tools :#{name}"
          say ""
        end
      end

      private

      def tool_template_path
        "app/views/#{agent_name.underscore}/tools/#{name}.json.erb"
      end

      def parse_parameters
        options[:parameters].map do |param|
          parts = param.split(":")
          {
            name: parts[0],
            type: parts[1] || "string",
            required: parts[2] == "required",
            description: parts[3] || "The #{parts[0].humanize.downcase}"
          }
        end
      end

      def tool_method_stub
        params_signature = @parameters.map do |p|
          if p[:required]
            "#{p[:name]}:"
          else
            "#{p[:name]}: nil"
          end
        end.join(", ")

        params_log = @parameters.map { |p| "\#{#{p[:name]}}" }.join(", ")

        <<~RUBY
          # Tool method: #{name.humanize}
          def #{name}(#{params_signature})
            Rails.logger.info "[#{agent_name}] Tool called: #{name}(#{params_log})"

            # TODO: Implement tool logic
            { success: true }
          rescue => e
            Rails.logger.error "[#{agent_name}] #{name.humanize} error: \#{e.message}"
            { success: false, error: e.message }
          end
        RUBY
      end

      def inline_tool_definition
        params_block = @parameters.map do |p|
          required_str = p[:required] ? ", required: true" : ""
          "    parameter :#{p[:name]}, type: :#{p[:type]}#{required_str}, description: \"#{p[:description]}\""
        end.join("\n")

        <<~RUBY
          tool :#{name} do
            description "#{@tool_description}"
          #{params_block}
          end
        RUBY
      end
    end
  end
end

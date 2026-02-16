# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module SolidAgent
  module Generators
    class ReasonsGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Adds reasoning columns to an existing generation model for extended thinking support"

      argument :model_name, type: :string, default: "AgentGeneration",
        desc: "The model to add reasoning columns to"

      class_option :content_column, type: :string, default: "reasoning_content",
        desc: "Column name for storing reasoning content"

      class_option :tokens_column, type: :string, default: "reasoning_tokens",
        desc: "Column name for storing reasoning token count"

      class_option :metadata_column, type: :string, default: "reasoning_metadata",
        desc: "Column name for storing reasoning metadata (JSON)"

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration
        @table_name = model_name.underscore.pluralize
        @content_column = options[:content_column]
        @tokens_column = options[:tokens_column]
        @metadata_column = options[:metadata_column]

        migration_template(
          "add_reasoning_columns.rb.erb",
          "db/migrate/add_reasoning_to_#{@table_name}.rb"
        )
      end

      def add_concern_to_model
        model_file = "app/models/#{model_name.underscore}.rb"

        return unless File.exist?(model_file)

        inject_into_class model_file, model_name do
          "  include SolidAgent::Reasonable\n\n"
        end

        say "Added SolidAgent::Reasonable to #{model_name}", :green
      end

      def show_post_install_message
        say ""
        say "Reasoning support added to #{model_name}!", :green
        say ""
        say "Next steps:", :yellow
        say "  1. Run migrations: rails db:migrate"
        say "  2. Use reasoning in your agents:"
        say ""
        say "     class MyAgent < ApplicationAgent"
        say "       include SolidAgent::HasReasons"
        say "       include SolidAgent::HasContext"
        say ""
        say "       has_reasons auto_capture: true, persist: true"
        say ""
        say "       def analyze"
        say "         result = prompt("
        say "           messages: messages,"
        say "           extended_thinking: true"
        say "         )"
        say ""
        say "         # Access reasoning"
        say "         last_reasoning.content"
        say "         total_reasoning_tokens"
        say "       end"
        say "     end"
        say ""
      end
    end
  end
end

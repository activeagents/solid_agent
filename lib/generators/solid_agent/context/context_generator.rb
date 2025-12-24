# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module SolidAgent
  module Generators
    class ContextGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Generates a custom context model with migrations for domain-specific agent contexts"

      argument :agent_name, type: :string, required: false,
        desc: "The agent class name that will use this context (optional)"

      class_option :skip_migrations, type: :boolean, default: false,
        desc: "Skip generating migrations"

      def create_migrations
        return if options[:skip_migrations]

        migration_template "create_context.rb.erb",
          "db/migrate/create_#{table_name}.rb"

        migration_template "create_messages.rb.erb",
          "db/migrate/create_#{message_table_name}.rb"

        migration_template "create_generations.rb.erb",
          "db/migrate/create_#{generation_table_name}.rb"
      end

      def create_models
        template "context_model.rb.erb", "app/models/#{file_name}.rb"
        template "message_model.rb.erb", "app/models/#{message_file_name}.rb"
        template "generation_model.rb.erb", "app/models/#{generation_file_name}.rb"
      end

      def show_usage
        say ""
        say "Context models created!", :green
        say ""
        say "Files generated:"
        say "  app/models/#{file_name}.rb"
        say "  app/models/#{message_file_name}.rb"
        say "  app/models/#{generation_file_name}.rb"
        say "  db/migrate/*_create_#{table_name}.rb"
        say "  db/migrate/*_create_#{message_table_name}.rb"
        say "  db/migrate/*_create_#{generation_table_name}.rb"
        say ""
        say "Next steps:", :yellow
        say "  1. Run migrations: rails db:migrate"
        say ""
        say "  2. Add to your agent:"
        say "     class #{agent_class_name} < ApplicationAgent"
        say "       include SolidAgent::HasContext"
        say "       has_context :#{context_name}"
        say ""
        say "       def perform"
        say "         create_#{context_name}(contextable: params[:user])"
        say "         prompt"
        say "       end"
        say "     end"
        say ""
      end

      private

      def context_name
        name.underscore.singularize
      end

      def class_name
        name.camelize
      end

      def file_name
        name.underscore
      end

      def table_name
        name.underscore.pluralize
      end

      def message_class_name
        "#{class_name}Message"
      end

      def message_file_name
        "#{file_name}_message"
      end

      def message_table_name
        "#{file_name}_messages"
      end

      def generation_class_name
        "#{class_name}Generation"
      end

      def generation_file_name
        "#{file_name}_generation"
      end

      def generation_table_name
        "#{file_name}_generations"
      end

      def agent_class_name
        agent_name&.camelize || "MyAgent"
      end

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end
    end
  end
end

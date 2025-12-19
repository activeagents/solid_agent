# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module SolidAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs SolidAgent: creates migrations for context persistence and initializer"

      class_option :skip_migrations, type: :boolean, default: false,
        desc: "Skip generating migrations"

      class_option :skip_initializer, type: :boolean, default: false,
        desc: "Skip generating initializer"

      def create_migrations
        return if options[:skip_migrations]

        migration_template "create_agent_contexts.rb.erb",
          "db/migrate/create_agent_contexts.rb"

        migration_template "create_agent_messages.rb.erb",
          "db/migrate/create_agent_messages.rb"

        migration_template "create_agent_generations.rb.erb",
          "db/migrate/create_agent_generations.rb"
      end

      def create_models
        return if options[:skip_migrations]

        template "agent_context.rb.erb", "app/models/agent_context.rb"
        template "agent_message.rb.erb", "app/models/agent_message.rb"
        template "agent_generation.rb.erb", "app/models/agent_generation.rb"
      end

      def create_initializer
        return if options[:skip_initializer]

        template "initializer.rb.erb", "config/initializers/solid_agent.rb"
      end

      def show_post_install_message
        say ""
        say "SolidAgent installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations: rails db:migrate"
        say "  2. Include SolidAgent::HasContext in your ApplicationAgent"
        say "  3. Use has_context in agents that need persistence"
        say ""
        say "Example:"
        say "  class WritingAssistantAgent < ApplicationAgent"
        say "    include SolidAgent::HasContext"
        say "    has_context"
        say ""
        say "    def improve"
        say "      create_context(contextable: params[:document])"
        say "      prompt"
        say "    end"
        say "  end"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      # Ensure unique timestamps for multiple migrations
      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end
    end
  end
end

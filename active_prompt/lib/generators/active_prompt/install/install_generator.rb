# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module ActivePrompt
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs ActivePrompt and generates the necessary files"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migrations
        migration_template "create_active_prompt_prompts.rb",
                           "db/migrate/create_active_prompt_prompts.rb"
        migration_template "create_active_prompt_sessions.rb",
                           "db/migrate/create_active_prompt_sessions.rb"
        migration_template "create_active_prompt_fragments.rb",
                           "db/migrate/create_active_prompt_fragments.rb"
        migration_template "create_active_prompt_messages.rb",
                           "db/migrate/create_active_prompt_messages.rb"
      end

      def create_initializer
        template "initializer.rb", "config/initializers/active_prompt.rb"
      end

      def mount_routes
        route 'mount ActivePrompt::Engine => "/active_prompt"'
      end

      def show_post_install_message
        say ""
        say "ActivePrompt has been installed!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations: rails db:migrate"
        say "  2. Configure ActivePrompt in config/initializers/active_prompt.rb"
        say "  3. Create your first browser agent prompt"
        say ""
        say "Example usage:"
        say '  # Create a prompt'
        say '  prompt = ActivePrompt::Prompt.create!('
        say '    name: "browser-assistant",'
        say '    model: "anthropic/claude-sonnet-4-20250514",'
        say '    instructions: "You are a browser automation assistant..."'
        say '  )'
        say ""
        say '  # Execute a task'
        say '  result = ActivePrompt::BrowserAgent.execute_task('
        say '    "Go to github.com and find trending repositories"'
        say '  )'
        say ""
      end
    end
  end
end

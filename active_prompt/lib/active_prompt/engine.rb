# frozen_string_literal: true

module ActivePrompt
  class Engine < ::Rails::Engine
    isolate_namespace ActivePrompt

    config.autoload_paths << File.expand_path("../../app/models", __dir__)
    config.autoload_paths << File.expand_path("../../app/controllers", __dir__)
    config.autoload_paths << File.expand_path("../../app/jobs", __dir__)
    config.autoload_paths << File.expand_path("../../app/channels", __dir__)

    initializer "active_prompt.setup" do |app|
      # Load SolidAgent integration
      require "solid_agent" if defined?(SolidAgent)
    end

    initializer "active_prompt.action_cable" do
      ActiveSupport.on_load(:action_cable) do
        # Register channels for real-time updates
      end
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end
  end
end

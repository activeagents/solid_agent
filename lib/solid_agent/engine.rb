# frozen_string_literal: true

module SolidAgent
  class Engine < ::Rails::Engine
    isolate_namespace SolidAgent

    # Add generators to the Rails generator lookup path
    config.generators do |g|
      g.test_framework :minitest
    end

    initializer "solid_agent.load_generators" do
      # Generators are automatically loaded from lib/generators
    end
  end
end

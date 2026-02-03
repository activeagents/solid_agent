# frozen_string_literal: true

require_relative "lib/active_prompt/version"

Gem::Specification.new do |spec|
  spec.name = "active_prompt"
  spec.version = ActivePrompt::VERSION
  spec.authors = ["ActiveAgents Team"]
  spec.email = ["team@activeagents.ai"]

  spec.summary = "Rails engine for versioned AI agent prompts with fragment-based context management"
  spec.description = "ActivePrompt provides a Rails engine for managing AI agent configurations, " \
                     "versioning prompts, and persisting conversation fragments. It integrates with " \
                     "SolidAgent for browser automation agents with Playwright MCP support."
  spec.homepage = "https://github.com/activeagents/active_prompt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "solid_agent", ">= 0.1.0"
  spec.add_dependency "activeagent", ">= 1.0.0"

  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "factory_bot_rails"
end

# frozen_string_literal: true

require_relative "lib/solid_agent/version"

Gem::Specification.new do |spec|
  spec.name = "solid_agent"
  spec.version = SolidAgent::VERSION
  spec.authors = ["Justin Bowen"]
  spec.email = ["JusBowen@gmail.com"]

  spec.summary = "Database-backed context, tools, and streaming for ActiveAgent"
  spec.description = "SolidAgent extends ActiveAgent with database-backed prompt context management, declarative tool schemas, and real-time streaming updates. Provides has_context, has_tools, and streams_tool_updates concerns for building robust AI agents."
  spec.homepage = "https://docs.activeagents.ai/solid_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/activeagents/solid_agent"
  spec.metadata["changelog_uri"] = "https://github.com/activeagents/solid_agent/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://docs.activeagents.ai/solid_agent"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activeagent", ">= 1.0.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
end

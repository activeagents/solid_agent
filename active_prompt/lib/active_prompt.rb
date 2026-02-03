# frozen_string_literal: true

require "active_prompt/version"
require "active_prompt/engine"
require "active_prompt/configuration"
require "active_prompt/fragment_cache"
require "active_prompt/browser_session"
require "active_prompt/browser_agent"
require "active_prompt/agent_loader"
require "active_prompt/agents/github_trends_agent"

module ActivePrompt
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class VersionMismatchError < Error; end
  class FragmentNotFoundError < Error; end
  class SessionExpiredError < Error; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Registry for versioned prompt configurations
    def prompt_registry
      @prompt_registry ||= {}
    end

    # Register a prompt configuration with version tracking
    def register_prompt(name, version:, config:)
      prompt_registry[name] ||= {}
      prompt_registry[name][version] = config
    end

    # Get a specific version of a prompt
    def get_prompt(name, version: :latest)
      versions = prompt_registry[name]
      raise ConfigurationError, "Prompt '#{name}' not found" unless versions

      if version == :latest
        latest_version = versions.keys.max_by { |v| Gem::Version.new(v) }
        versions[latest_version]
      else
        versions[version] || raise(VersionMismatchError, "Version '#{version}' not found for prompt '#{name}'")
      end
    end

    # List all registered prompts with their versions
    def list_prompts
      prompt_registry.transform_values(&:keys)
    end
  end
end

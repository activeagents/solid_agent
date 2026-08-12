# frozen_string_literal: true

require_relative "solid_agent/version"
require_relative "solid_agent/tool_cache"
require_relative "solid_agent/model_pricing"
require_relative "solid_agent/run_fingerprint"

module SolidAgent
  class Error < StandardError; end
  class LoadError < Error; end

  class << self
    attr_accessor :context_class, :message_class, :generation_class

    def configure
      yield self if block_given?
    end

    # Unified agent loading from any source
    #
    # @param source [String, Hash, URI] File path, URL, JSON, YAML, or Hash
    # @param format [Symbol] Force format (:agent_md, :json, :yaml, :dotprompt, :crewai)
    # @param base_class [Class] Parent class for generated agent
    # @param as [String] Register as constant with this name
    # @return [Class] Generated agent class
    #
    # @example Load from file
    #   ResearchAgent = SolidAgent.agent("agents/research.agent.md")
    #
    # @example Load from URL
    #   WeatherAgent = SolidAgent.agent("https://registry.example.com/weather.agent.md")
    #
    # @example Load from hash
    #   QuickAgent = SolidAgent.agent({ name: "quick", model: "gpt-4o", instructions: "Be helpful" })
    #
    def agent(source, format: nil, base_class: nil, as: nil)
      manifest = AgentManifest.load(source, format: format)
      AgentManifest.build(manifest, base_class: base_class, class_name: as)
    end

    # Load multiple agents from a directory
    #
    # @param directory [String] Path to directory containing agent manifests
    # @param pattern [String] Glob pattern for manifest files
    # @param options [Hash] Options passed to agent()
    # @return [Array<Class>] Array of generated agent classes
    #
    # @example Load all agents from config/agents
    #   SolidAgent.agents_from("config/agents")
    #
    def agents_from(directory, pattern: "**/*.agent.md", **options)
      Dir.glob(File.join(directory, pattern)).map do |path|
        agent(path, **options)
      end
    end
  end

  # Default configuration
  self.context_class = "AgentContext"
  self.message_class = "AgentMessage"
  self.generation_class = "AgentGeneration"
end

require_relative "solid_agent/has_context"
require_relative "solid_agent/has_memory"
require_relative "solid_agent/has_tools"
require_relative "solid_agent/delegates"
require_relative "solid_agent/streams_tool_updates"
require_relative "solid_agent/reasonable"
require_relative "solid_agent/has_reasons"
require_relative "solid_agent/agent_manifest"

# Load Rails integration if Rails is present
if defined?(Rails::Engine)
  require_relative "solid_agent/engine"
end

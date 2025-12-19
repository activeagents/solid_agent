# frozen_string_literal: true

require_relative "solid_agent/version"
require_relative "solid_agent/has_context"
require_relative "solid_agent/has_tools"
require_relative "solid_agent/streams_tool_updates"

module SolidAgent
  class Error < StandardError; end

  class << self
    attr_accessor :context_class, :message_class, :generation_class

    def configure
      yield self if block_given?
    end
  end

  # Default configuration
  self.context_class = "AgentContext"
  self.message_class = "AgentMessage"
  self.generation_class = "AgentGeneration"
end

# Load Rails integration if Rails is present
if defined?(Rails::Engine)
  require_relative "solid_agent/engine"
end

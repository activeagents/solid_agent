# frozen_string_literal: true

module ActivePrompt
  # Configuration for ActivePrompt engine
  #
  # @example Configure in an initializer
  #   ActivePrompt.configure do |config|
  #     config.default_model = "anthropic/claude-sonnet-4-20250514"
  #     config.fragment_cache_store = :redis
  #     config.session_timeout = 30.minutes
  #     config.playwright_mcp_endpoint = "http://localhost:3001"
  #   end
  #
  class Configuration
    # Default model for prompts
    attr_accessor :default_model

    # Fragment cache store (:memory, :redis, :database)
    attr_accessor :fragment_cache_store

    # Session timeout for browser sessions
    attr_accessor :session_timeout

    # Playwright MCP server endpoint
    attr_accessor :playwright_mcp_endpoint

    # Whether to auto-persist fragments
    attr_accessor :auto_persist_fragments

    # Maximum fragments per session
    attr_accessor :max_fragments_per_session

    # Base class for generated agents
    attr_accessor :agent_base_class

    # Enable extended thinking capture
    attr_accessor :capture_reasoning

    # Default reasoning token budget
    attr_accessor :reasoning_budget_tokens

    # Authentication callback for browser sessions
    attr_accessor :auth_callback

    # Session state change callback
    attr_accessor :on_session_state_change

    # Prompt version strategy (:semver, :timestamp, :auto)
    attr_accessor :version_strategy

    def initialize
      @default_model = "anthropic/claude-sonnet-4-20250514"
      @fragment_cache_store = :database
      @session_timeout = 30.minutes
      @playwright_mcp_endpoint = nil
      @auto_persist_fragments = true
      @max_fragments_per_session = 100
      @agent_base_class = "ApplicationAgent"
      @capture_reasoning = true
      @reasoning_budget_tokens = 10_000
      @auth_callback = nil
      @on_session_state_change = nil
      @version_strategy = :semver
    end

    # Validate configuration
    def validate!
      raise ConfigurationError, "default_model is required" if default_model.blank?

      unless %i[memory redis database].include?(fragment_cache_store)
        raise ConfigurationError, "fragment_cache_store must be :memory, :redis, or :database"
      end

      unless %i[semver timestamp auto].include?(version_strategy)
        raise ConfigurationError, "version_strategy must be :semver, :timestamp, or :auto"
      end

      true
    end
  end
end

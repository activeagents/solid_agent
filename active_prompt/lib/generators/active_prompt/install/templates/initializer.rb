# frozen_string_literal: true

ActivePrompt.configure do |config|
  # Default model for prompts
  # config.default_model = "anthropic/claude-sonnet-4-20250514"

  # Fragment cache store (:memory, :redis, :database)
  # config.fragment_cache_store = :database

  # Session timeout (default: 30 minutes)
  # config.session_timeout = 30.minutes

  # Playwright MCP server endpoint (if using external server)
  # config.playwright_mcp_endpoint = "http://localhost:3001"

  # Auto-persist fragments to database
  # config.auto_persist_fragments = true

  # Maximum fragments per session
  # config.max_fragments_per_session = 100

  # Base class for generated agents
  # config.agent_base_class = "ApplicationAgent"

  # Enable extended thinking/reasoning capture
  # config.capture_reasoning = true

  # Default reasoning token budget
  # config.reasoning_budget_tokens = 10_000

  # Version strategy for prompts (:semver, :timestamp, :auto)
  # config.version_strategy = :semver

  # Callback when authentication is required during browser automation
  # config.auth_callback = ->(session, error) {
  #   # Notify user that authentication is needed
  #   # e.g., send email, push notification, etc.
  # }

  # Callback when session state changes
  # config.on_session_state_change = ->(session, old_state, new_state) {
  #   # Log state changes, update UI, etc.
  # }
end

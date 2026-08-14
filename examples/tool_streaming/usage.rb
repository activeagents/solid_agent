# frozen_string_literal: true

# Tools, live status and caching — rails console walkthrough.
#
# Docs: https://docs.activeagents.ai/solid_agent/tools

# What the agent will send to the provider: the template-loaded schema
# first, then the inline one.
BrowserAgent.new.tools.map { |t| t[:name] }
# => ["fetch_url", "summarize_page"]

# Editing a JSON template while the server is running? Drop the cache:
agent = BrowserAgent.new
agent.reload_tools!

# Without a stream_id nothing is broadcast — the same agent runs silently
# from a job or a console.
BrowserAgent.with(message: "Summarize https://rubyonrails.org").browse.generate_now

# With one, every described tool announces itself before it runs:
#   { tool_status: { name: "fetch_url",
#                    description: "Fetching https://rubyonrails.org...",
#                    timestamp: "2026-08-14T12:00:00Z" } }
stream_id = "tool_status:#{current_user.id}:#{SecureRandom.uuid}"

BrowserAgent.with(
  stream_id: stream_id,
  message: "Summarize https://rubyonrails.org"
).browse.generate_now

# --- Tool cache ---------------------------------------------------------

# The cache is keyed by (tool, normalized args) — argument order and
# symbol/string keys don't change the key.
SolidAgent::ToolCache.cache_key("fetch_url", { url: "https://example.com" })
# => "solid_agent:tool_cache:fetch_url:9f2c..."

result = SolidAgent::ToolCache.fetch(tool: "fetch_url", args: { url: "https://example.com" }) do
  { body: "expensive" }
end
result[:cached] # => nil on the first call, true on a replay

# Backed by Rails.cache by default; swap the store (or switch it off) in
# tests and non-Rails runtimes.
SolidAgent::ToolCache.store = ActiveSupport::Cache::MemoryStore.new
SolidAgent::ToolCache.default_ttl = 60
SolidAgent::ToolCache.enabled = false

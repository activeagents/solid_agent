# frozen_string_literal: true

# Rails does not guarantee net/http is loaded, and fetch_url below needs it.
require "net/http"

# Tools three ways, plus live progress and result caching.
#
# - `has_tools :fetch_url` loads a schema from a JSON view template, so the
#   schema lives next to the rest of the agent's views and can use ERB.
# - `tool :summarize_page do ... end` defines a schema inline.
# - `tool_description` wraps the tool method so each call broadcasts a
#   human-readable status over ActionCable before it runs.
# - `SolidAgent::ToolCache.fetch` replays an identical call instead of
#   paying for the side effect twice.
#
# Docs: https://docs.activeagents.ai/solid_agent/tools
class BrowserAgent < ApplicationAgent
  include SolidAgent::HasTools
  include SolidAgent::StreamsToolUpdates

  generate_with :openai, model: "gpt-4o-mini"

  # Loaded from app/views/browser_agent/tools/fetch_url.json.erb.
  # `has_tools` with no arguments discovers every template in that
  # directory instead.
  has_tools :fetch_url

  tool :summarize_page do
    description "Summarize text that was already fetched"
    parameter :text, type: :string, required: true, description: "Page text to summarize"
    parameter :sentences, type: :integer, default: 3
  end

  # Static or dynamic — a proc receives the tool's arguments. Declaring a
  # description is what wraps the method for broadcasting; tools without
  # one still run, they just stay quiet.
  tool_description :fetch_url, ->(args) { "Fetching #{args[:url]}..." }
  tool_description :summarize_page, "Summarizing the page..."

  def browse
    # `tools` is every schema this agent declares: templates first, then
    # inline definitions.
    prompt tools: tools
  end

  # Tool methods take keyword arguments and are named after the schema.
  def fetch_url(url:)
    # Identical (tool, args) pairs inside the TTL replay the stored result
    # and come back tagged cached: true. Error-shaped results are never
    # cached, so a transient failure doesn't stick for five minutes.
    SolidAgent::ToolCache.fetch(tool: "fetch_url", args: { url: url }, ttl: 5.minutes) do
      response = Net::HTTP.get_response(URI(url))

      if response.is_a?(Net::HTTPSuccess)
        { url: url, body: response.body.first(10_000) }
      else
        { error: "HTTP #{response.code}" }
      end
    end
  end

  def summarize_page(text:, sentences: 3)
    { summary: text.split(/(?<=\.)\s+/).first(sentences).join(" ") }
  end
end

# frozen_string_literal: true

require "test_helper"
require "solid_agent/tool_cache"

class SolidAgent::ToolCacheTest < Minitest::Test
  # Minimal store with the read/write contract ToolCache needs.
  class MemoryStore
    attr_reader :writes

    def initialize
      @data = {}
      @writes = []
    end

    def read(key)
      @data[key]
    end

    def write(key, value, **options)
      @writes << [ key, value, options ]
      @data[key] = value
    end
  end

  def setup
    @store = MemoryStore.new
  end

  def test_caches_and_replays_results
    calls = 0
    2.times do
      @result = SolidAgent::ToolCache.fetch(tool: "web_search", args: { query: "rails" }, cache: @store) do
        calls += 1
        { answer: 42 }
      end
    end

    assert_equal 1, calls
    assert_equal 42, @result[:answer]
    assert_equal true, @result[:cached], "replayed results should be tagged cached: true"
  end

  def test_key_is_stable_across_argument_ordering_and_key_types
    key_a = SolidAgent::ToolCache.cache_key("t", { a: 1, b: 2 })
    key_b = SolidAgent::ToolCache.cache_key("t", { "b" => 2, "a" => 1 })
    key_c = SolidAgent::ToolCache.cache_key("t", { a: 1, b: 3 })

    assert_equal key_a, key_b
    refute_equal key_a, key_c
  end

  def test_does_not_cache_error_results
    2.times do
      SolidAgent::ToolCache.fetch(tool: "fetch_url", args: { url: "x" }, cache: @store) do
        { error: "boom" }
      end
    end

    assert_empty @store.writes
  end

  def test_respects_ttl_option
    SolidAgent::ToolCache.fetch(tool: "t", args: {}, ttl: 60, cache: @store) { { ok: true } }

    assert_equal 60, @store.writes.first.last[:expires_in]
  end

  def test_disabled_bypasses_cache
    SolidAgent::ToolCache.enabled = false
    calls = 0
    2.times do
      SolidAgent::ToolCache.fetch(tool: "t", args: {}, cache: @store) { calls += 1; { ok: true } }
    end

    assert_equal 2, calls
    assert_empty @store.writes
  ensure
    SolidAgent::ToolCache.enabled = true
  end

  def test_yields_without_a_store
    result = SolidAgent::ToolCache.fetch(tool: "t", args: {}, cache: nil) { { ok: true } }

    assert_equal({ ok: true }, result)
  end
end

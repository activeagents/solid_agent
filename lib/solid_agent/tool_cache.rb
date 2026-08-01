# frozen_string_literal: true

require "digest"
require "json"

# Caches the results of tool / MCP / service interactions so repeated calls
# with the same arguments reuse a persisted result instead of re-running the
# side effect (HTTP fetch, search, remote MCP call, ...).
#
# Works out of the box in Rails apps (backed by Rails.cache); any object
# responding to read/write can be substituted, so tests and non-Rails
# runtimes can inject their own store.
#
# @example Caching a tool implementation
#   def fetch_url(url:)
#     SolidAgent::ToolCache.fetch(tool: "fetch_url", args: { url: url }) do
#       Net::HTTP.get_response(URI(url)).body
#     end
#   end
#
# @example Disabling globally (e.g. in tests)
#   SolidAgent::ToolCache.enabled = false
module SolidAgent
  module ToolCache
    DEFAULT_TTL = 300 # seconds

    class << self
      attr_writer :enabled, :default_ttl, :store

      def enabled
        defined?(@enabled) ? @enabled : true
      end

      def default_ttl
        @default_ttl || DEFAULT_TTL
      end

      def store
        @store || (defined?(Rails) && Rails.respond_to?(:cache) ? Rails.cache : nil)
      end

      # Returns the cached result for (tool, args) or yields, caching the
      # fresh result. Results that look like errors ({ error: ... }) are
      # never cached, so transient failures don't stick.
      #
      # The returned hash is tagged with cached: true on cache hits so
      # callers (and the model) can tell a replayed result from a fresh one.
      def fetch(tool:, args: {}, ttl: nil, cache: store)
        return yield unless enabled && cache

        key = cache_key(tool, args)
        cached = cache.read(key)
        return tag_cached(cached) unless cached.nil?

        result = yield
        cache.write(key, result, expires_in: ttl || default_ttl) if cacheable?(result)
        result
      end

      def cache_key(tool, args)
        digest = Digest::SHA256.hexdigest(normalize_args(args).to_json)
        "solid_agent:tool_cache:#{tool}:#{digest}"
      end

      private

      def cacheable?(result)
        return false if result.nil?
        return !(result.key?(:error) || result.key?("error")) if result.respond_to?(:key?)

        true
      end

      def tag_cached(result)
        result.respond_to?(:merge) ? result.merge(cached: true) : result
      end

      # Stable key material regardless of hash ordering or string/symbol keys.
      def normalize_args(args)
        case args
        when Hash
          args.map { |k, v| [ k.to_s, normalize_args(v) ] }.sort_by(&:first)
        when Array
          args.map { |v| normalize_args(v) }
        else
          args
        end
      end
    end
  end
end

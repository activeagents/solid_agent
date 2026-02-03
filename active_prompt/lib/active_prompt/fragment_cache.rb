# frozen_string_literal: true

module ActivePrompt
  # FragmentCache provides efficient caching for session fragments.
  #
  # Supports multiple backends (:memory, :redis, :database) and provides
  # a unified interface for storing and retrieving fragment data.
  #
  # @example Using the fragment cache
  #   cache = ActivePrompt::FragmentCache.new
  #   cache.store(session_id, :browser_state, state_data)
  #   state = cache.fetch(session_id, :browser_state)
  #
  class FragmentCache
    attr_reader :backend

    def initialize(backend: nil)
      @backend = backend || ActivePrompt.configuration.fragment_cache_store
      @memory_store = {}
    end

    # Store a fragment in the cache
    #
    # @param session_id [Integer, String] Session identifier
    # @param fragment_type [Symbol] Type of fragment
    # @param data [Hash] Fragment data
    # @param ttl [Integer] Time to live in seconds (optional)
    # @return [Boolean]
    def store(session_id, fragment_type, data, ttl: nil)
      key = cache_key(session_id, fragment_type)
      ttl ||= default_ttl

      case backend
      when :memory
        store_memory(key, data, ttl)
      when :redis
        store_redis(key, data, ttl)
      when :database
        store_database(session_id, fragment_type, data)
      else
        raise ConfigurationError, "Unknown cache backend: #{backend}"
      end

      true
    end

    # Fetch a fragment from the cache
    #
    # @param session_id [Integer, String] Session identifier
    # @param fragment_type [Symbol] Type of fragment
    # @return [Hash, nil]
    def fetch(session_id, fragment_type)
      key = cache_key(session_id, fragment_type)

      case backend
      when :memory
        fetch_memory(key)
      when :redis
        fetch_redis(key)
      when :database
        fetch_database(session_id, fragment_type)
      end
    end

    # Fetch or compute a fragment
    #
    # @param session_id [Integer, String] Session identifier
    # @param fragment_type [Symbol] Type of fragment
    # @param ttl [Integer] Time to live (optional)
    # @yield Block to compute value if not cached
    # @return [Hash]
    def fetch_or_store(session_id, fragment_type, ttl: nil, &block)
      cached = fetch(session_id, fragment_type)
      return cached if cached

      data = block.call
      store(session_id, fragment_type, data, ttl: ttl)
      data
    end

    # Delete a fragment from the cache
    #
    # @param session_id [Integer, String] Session identifier
    # @param fragment_type [Symbol] Type of fragment
    # @return [Boolean]
    def delete(session_id, fragment_type)
      key = cache_key(session_id, fragment_type)

      case backend
      when :memory
        @memory_store.delete(key)
      when :redis
        redis_client.del(key)
      when :database
        # Don't delete from database - mark as deleted instead
        false
      end

      true
    end

    # Delete all fragments for a session
    #
    # @param session_id [Integer, String] Session identifier
    # @return [Boolean]
    def clear_session(session_id)
      case backend
      when :memory
        @memory_store.delete_if { |k, _| k.start_with?("session:#{session_id}:") }
      when :redis
        keys = redis_client.keys("session:#{session_id}:*")
        redis_client.del(*keys) if keys.any?
      when :database
        # Database fragments are managed by Session lifecycle
        false
      end

      true
    end

    # Get all fragment types for a session
    #
    # @param session_id [Integer, String] Session identifier
    # @return [Array<Symbol>]
    def fragment_types(session_id)
      case backend
      when :memory
        @memory_store
          .keys
          .select { |k| k.start_with?("session:#{session_id}:") }
          .map { |k| k.split(":").last.to_sym }
      when :redis
        keys = redis_client.keys("session:#{session_id}:*")
        keys.map { |k| k.split(":").last.to_sym }
      when :database
        Session.find(session_id).fragments.pluck(:fragment_type).uniq.map(&:to_sym)
      end
    end

    private

    def cache_key(session_id, fragment_type)
      "session:#{session_id}:#{fragment_type}"
    end

    def default_ttl
      ActivePrompt.configuration.session_timeout.to_i
    end

    # Memory backend methods
    def store_memory(key, data, ttl)
      @memory_store[key] = {
        data: data,
        expires_at: Time.current + ttl
      }
    end

    def fetch_memory(key)
      entry = @memory_store[key]
      return nil unless entry
      return nil if entry[:expires_at] < Time.current

      entry[:data]
    end

    # Redis backend methods
    def store_redis(key, data, ttl)
      redis_client.setex(key, ttl, data.to_json)
    end

    def fetch_redis(key)
      data = redis_client.get(key)
      return nil unless data

      JSON.parse(data, symbolize_names: true)
    end

    def redis_client
      @redis_client ||= begin
        if defined?(Redis)
          Redis.current
        else
          raise ConfigurationError, "Redis gem is required for redis cache backend"
        end
      end
    end

    # Database backend methods
    def store_database(session_id, fragment_type, data)
      session = Session.find(session_id)
      session.add_fragment(type: fragment_type, content: data)
    end

    def fetch_database(session_id, fragment_type)
      session = Session.find_by(id: session_id)
      return nil unless session

      fragment = session.latest_fragment(fragment_type)
      fragment&.content
    end
  end
end

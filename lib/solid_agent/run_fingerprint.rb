# frozen_string_literal: true

require "digest"

module SolidAgent
  # Stable fingerprints for the instructions a run executed under — the
  # grouping key (with model) for configuration cohorts when comparing
  # instruction/model changes across runs.
  #
  # @example Digest and codename
  #   digest = SolidAgent::RunFingerprint.digest("You are a helpful agent.")
  #   # => "a1b2c3d4"
  #   SolidAgent::RunFingerprint.codename(digest)
  #   # => "calm-heron"
  module RunFingerprint
    # Deterministic memorable names for digests — they read far better
    # than hex when comparing cohorts, and are stable across runs and
    # deployments because they derive from the digest alone.
    ADJECTIVES = %w[
      calm brisk quiet bold amber coral dusky fresh golden keen
      lively mellow nimble pale rustic silver tidal vivid wry zesty
      arid breezy crisp dapper eager foggy hazy icy jolly lunar
      misty polar
    ].freeze
    NOUNS = %w[
      heron otter falcon cedar willow harbor mesa ridge grove delta
      prairie summit canyon reef atoll fjord tundra oasis lagoon dune
      glacier meadow bluff cove marsh basin knoll strait quarry vale
      hollow crag
    ].freeze

    class << self
      # @param instructions [String, nil]
      # @return [String, nil] 8-hex-char digest, nil for blank input
      def digest(instructions)
        return nil if instructions.nil? || instructions.to_s.strip.empty?

        Digest::SHA256.hexdigest(instructions.to_s)[0, 8]
      end

      # @param digest [String, nil] an 8-hex-char instructions digest
      # @return [String, nil] deterministic "adjective-noun" codename
      def codename(digest)
        return nil if digest.nil? || digest.to_s.empty?

        value = digest.to_s.to_i(16)
        "#{ADJECTIVES[value % 32]}-#{NOUNS[(value / 32) % 32]}"
      end
    end
  end
end

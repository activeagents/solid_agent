# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActivePrompt::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "has default_model" do
      expect(config.default_model).to eq("anthropic/claude-sonnet-4-20250514")
    end

    it "has fragment_cache_store" do
      expect(config.fragment_cache_store).to eq(:database)
    end

    it "has session_timeout" do
      expect(config.session_timeout).to eq(30.minutes)
    end

    it "has auto_persist_fragments" do
      expect(config.auto_persist_fragments).to eq(true)
    end

    it "has max_fragments_per_session" do
      expect(config.max_fragments_per_session).to eq(100)
    end

    it "has capture_reasoning" do
      expect(config.capture_reasoning).to eq(true)
    end

    it "has version_strategy" do
      expect(config.version_strategy).to eq(:semver)
    end
  end

  describe "#validate!" do
    it "passes with valid configuration" do
      expect { config.validate! }.not_to raise_error
    end

    it "raises error when default_model is blank" do
      config.default_model = nil
      expect { config.validate! }.to raise_error(ActivePrompt::ConfigurationError, /default_model/)
    end

    it "raises error for invalid fragment_cache_store" do
      config.fragment_cache_store = :invalid
      expect { config.validate! }.to raise_error(ActivePrompt::ConfigurationError, /fragment_cache_store/)
    end

    it "raises error for invalid version_strategy" do
      config.version_strategy = :invalid
      expect { config.validate! }.to raise_error(ActivePrompt::ConfigurationError, /version_strategy/)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActivePrompt do
  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(ActivePrompt.configuration).to be_a(ActivePrompt::Configuration)
    end

    it "allows configuration via block" do
      ActivePrompt.configure do |config|
        config.default_model = "test/model"
      end

      expect(ActivePrompt.configuration.default_model).to eq("test/model")
    end
  end

  describe ".reset_configuration!" do
    it "resets to default configuration" do
      ActivePrompt.configure do |config|
        config.default_model = "custom/model"
      end

      ActivePrompt.reset_configuration!

      expect(ActivePrompt.configuration.default_model).to eq("anthropic/claude-sonnet-4-20250514")
    end
  end

  describe "prompt registry" do
    before { ActivePrompt.instance_variable_set(:@prompt_registry, {}) }

    describe ".register_prompt" do
      it "registers a prompt with version" do
        ActivePrompt.register_prompt("test-agent", version: "1.0.0", config: { model: "test" })

        expect(ActivePrompt.prompt_registry["test-agent"]["1.0.0"]).to eq({ model: "test" })
      end
    end

    describe ".get_prompt" do
      before do
        ActivePrompt.register_prompt("test-agent", version: "1.0.0", config: { v: 1 })
        ActivePrompt.register_prompt("test-agent", version: "1.1.0", config: { v: 2 })
        ActivePrompt.register_prompt("test-agent", version: "2.0.0", config: { v: 3 })
      end

      it "returns specific version" do
        config = ActivePrompt.get_prompt("test-agent", version: "1.1.0")
        expect(config[:v]).to eq(2)
      end

      it "returns latest version when version is :latest" do
        config = ActivePrompt.get_prompt("test-agent", version: :latest)
        expect(config[:v]).to eq(3)
      end

      it "raises ConfigurationError for unknown prompt" do
        expect {
          ActivePrompt.get_prompt("unknown")
        }.to raise_error(ActivePrompt::ConfigurationError)
      end

      it "raises VersionMismatchError for unknown version" do
        expect {
          ActivePrompt.get_prompt("test-agent", version: "9.9.9")
        }.to raise_error(ActivePrompt::VersionMismatchError)
      end
    end

    describe ".list_prompts" do
      it "lists all prompts with their versions" do
        ActivePrompt.register_prompt("agent-a", version: "1.0.0", config: {})
        ActivePrompt.register_prompt("agent-a", version: "1.1.0", config: {})
        ActivePrompt.register_prompt("agent-b", version: "2.0.0", config: {})

        result = ActivePrompt.list_prompts

        expect(result["agent-a"]).to contain_exactly("1.0.0", "1.1.0")
        expect(result["agent-b"]).to contain_exactly("2.0.0")
      end
    end
  end
end

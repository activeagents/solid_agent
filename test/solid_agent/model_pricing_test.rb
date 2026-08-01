# frozen_string_literal: true

require "test_helper"

# SolidAgent::ModelPricing — token counts to estimated USD. The RubyLLM
# registry is absent in the gem test environment, so these exercise the
# static-table and default-rate paths (registry_rate returns nil without
# the gem loaded).
class ModelPricingTest < Minitest::Test
  def test_static_table_covers_current_models
    assert_equal [ 0.15, 0.60 ], SolidAgent::ModelPricing.static_rate("gpt-4o-mini")
    assert_equal [ 3.00, 15.00 ], SolidAgent::ModelPricing.static_rate("claude-sonnet-5")
    assert_equal [ 5.00, 25.00 ], SolidAgent::ModelPricing.static_rate("claude-opus-5")
    assert_equal [ 10.00, 50.00 ], SolidAgent::ModelPricing.static_rate("claude-fable-5")
    assert_equal [ 1.00, 5.00 ], SolidAgent::ModelPricing.static_rate("claude-haiku-4-5")
  end

  def test_older_generations_keep_legacy_rates
    assert_equal [ 0.80, 4.00 ], SolidAgent::ModelPricing.static_rate("claude-3-5-haiku-latest")
    assert_equal [ 15.00, 75.00 ], SolidAgent::ModelPricing.static_rate("claude-3-opus-20240229")
    assert_equal [ 5.00, 25.00 ], SolidAgent::ModelPricing.static_rate("claude-opus-4-5-20251101")
  end

  def test_self_hosted_models_price_at_open_weight_rate
    assert_equal [ 0.20, 0.60 ], SolidAgent::ModelPricing.static_rate("qwen3:8b")
    assert_equal [ 0.20, 0.60 ], SolidAgent::ModelPricing.static_rate("llama3.1:8b")
  end

  def test_mock_models_are_free
    assert_equal [ 0.0, 0.0 ], SolidAgent::ModelPricing.static_rate("mock-gpt-4o-mini")
  end

  def test_unknown_models_fall_back_to_blended_default
    assert_equal SolidAgent::ModelPricing::DEFAULT_RATE, SolidAgent::ModelPricing.rate_for("totally-unknown-xyz")
    assert_equal SolidAgent::ModelPricing::DEFAULT_RATE, SolidAgent::ModelPricing.rate_for(nil)
  end

  def test_registry_rate_is_nil_without_ruby_llm
    assert_nil SolidAgent::ModelPricing.registry_rate("gpt-4o")
  end

  def test_estimate_prices_input_and_output_separately
    cost = SolidAgent::ModelPricing.estimate(model: "gpt-4o", input_tokens: 1_000_000, output_tokens: 1_000_000)
    assert_in_delta 12.5, cost, 0.001
  end

  def test_estimate_returns_nil_with_nothing_to_price
    assert_nil SolidAgent::ModelPricing.estimate(model: "gpt-4o", input_tokens: 0, output_tokens: 0)
  end
end

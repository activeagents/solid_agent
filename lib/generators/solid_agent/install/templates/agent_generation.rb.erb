# frozen_string_literal: true

# AgentGeneration stores the results of LLM generation calls.
#
# Each generation represents a single API call to the LLM provider,
# tracking the response, token usage, and any tool calls made.
#
# @example Accessing generation data
#   generation = context.generations.last
#   puts "Model: #{generation.model}"
#   puts "Tokens: #{generation.input_tokens} in, #{generation.output_tokens} out"
#   puts "Duration: #{generation.duration_seconds}s"
#
class AgentGeneration < ApplicationRecord
  # Associations
  belongs_to :agent_context

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_model, ->(model) { where(model: model) }
  scope :with_tool_calls, -> { where.not(tool_calls: []) }
  scope :with_trace, ->(trace_id) { where(trace_id: trace_id) }
  scope :completed, -> { where(finish_reason: "stop") }

  # Returns total token count for this generation
  def total_tokens
    input_tokens + output_tokens
  end

  # Provider prompt-cache hit on this generation?
  def cache_hit?
    cached_tokens.to_i.positive?
  end

  # Extended thinking captured?
  def thinking?
    reasoning_tokens.to_i.positive?
  end

  # Check if this generation included tool calls
  def has_tool_calls?
    tool_calls.present? && tool_calls.any?
  end

  # Check if generation completed normally
  def completed?
    finish_reason == "stop"
  end

  # Check if generation was truncated due to length
  def truncated?
    finish_reason == "length"
  end

  # Check if generation ended with tool calls
  def ended_with_tool_calls?
    finish_reason == "tool_calls"
  end

  # Returns the cost estimate based on token usage (override with your pricing)
  #
  # @param input_price_per_million [Float] price per million input tokens
  # @param output_price_per_million [Float, nil] price per million output tokens
  # @return [Float, nil] estimated cost in dollars, nil when nothing to price
  def estimated_cost(input_price_per_million: nil, output_price_per_million: nil)
    if input_price_per_million && output_price_per_million
      input_cost = (input_tokens / 1_000_000.0) * input_price_per_million
      output_cost = (output_tokens / 1_000_000.0) * output_price_per_million
      input_cost + output_cost
    else
      # Per-model rates from SolidAgent::ModelPricing (RubyLLM registry
      # when available, static table otherwise)
      SolidAgent::ModelPricing.estimate(model: model, input_tokens: input_tokens, output_tokens: output_tokens)
    end
  end
end

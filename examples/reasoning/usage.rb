# frozen_string_literal: true

# Reasoning capture — rails console walkthrough.
#
# Docs: https://docs.activeagents.ai/solid_agent/reasoning

document = Document.find(1)

AnalysisAgent.with(document: document).analyze.generate_now

# Persisted (persist: true + SolidAgent::Reasonable on the model). This is
# what survives the request:
generation = AgentGeneration.recent.first
generation.reasoning_content
generation.reasoning_tokens
generation.has_reasoning?
generation.reasoning_summary(length: 120)
generation.thinking?           # reasoning_tokens > 0 on the generated model

# In-memory, on the agent instance that ran — reachable from inside an
# action or a callback, not from the console after the fact:
#
#   def analyze
#     prompt(...)
#   end
#
#   def after_response
#     reasons                  # => [SolidAgent::Reasonable::Reason, ...]
#     last_reasoning&.content
#     total_reasoning_tokens
#     has_reasoning?
#     reasoning_chain          # every non-redacted reason, joined
#     reasoning_stats
#     # => { count: 2, total_tokens: 450, total_thinking_time_ms: 1200,
#     #      redacted_count: 0, models: ["claude-sonnet-5"] }
#   end

# Storing reasoning by hand — from a provider response, or as a note:
generation.store_reasoning!(response)
generation.store_reason!(
  SolidAgent::Reasonable::Reason.new(content: "Chose the strict parser", tokens: 0)
)

# Reasoning columns on any generation-shaped model:
#
#   rails generate solid_agent:reasons MyGeneration \
#     --content_column thinking_trace --tokens_column think_tokens
#
#   class MyGeneration < ApplicationRecord
#     include SolidAgent::Reasonable
#     reasonable_config column: :thinking_trace, tokens_column: :think_tokens
#   end

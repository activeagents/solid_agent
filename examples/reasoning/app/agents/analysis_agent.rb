# frozen_string_literal: true

# Capturing extended thinking.
#
# Models that expose reasoning (Claude's extended thinking, OpenAI's
# reasoning models) return it alongside the answer. HasReasons collects it
# on the agent instance and, with `persist: true`, writes it onto the
# generation record so it survives the request — as long as that model
# includes SolidAgent::Reasonable and has the columns:
#
#   rails generate solid_agent:reasons AgentGeneration
#   rails db:migrate
#
# Reasoning is model output about its own process: treat it as sensitive.
# `redact_on_persist: true` keeps the token counts and drops the text.
#
# Docs: https://docs.activeagents.ai/solid_agent/reasoning
class AnalysisAgent < ApplicationAgent
  include SolidAgent::HasContext
  include SolidAgent::HasReasons

  generate_with :anthropic, model: "claude-sonnet-5"

  # Reasoning is read off the response, so it has to be handed to
  # capture_reasoning once the provider has answered. Declared *before*
  # has_context on purpose: around callbacks nest in declaration order, so
  # this one wraps HasContext's — and by the time it runs, the generation
  # row that `persist: true` updates has been written.
  around_generation :capture_generation_reasoning

  has_context contextual: :document

  has_reasons auto_capture: true,       # reasoning_prompt_options asks for thinking
              persist: true,            # store on the generation record
              budget_tokens: 10_000,    # default thinking budget
              redact_on_persist: false  # true stores "[Redacted]" + tokens

  def analyze
    prompt(
      message: "What risks does this contract create for the buyer?",
      **reasoning_prompt_options # extended_thinking + budget from has_reasons
    )
  end

  private

  def capture_generation_reasoning
    response = yield
    capture_reasoning(response)
    response
  end
end

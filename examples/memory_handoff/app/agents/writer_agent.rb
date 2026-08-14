# frozen_string_literal: true

# Second half of the hand-off: a different agent class, same subject.
#
# Two ways to pick up what ResearcherAgent left behind:
#
#   1. Give the model the recall tool and let it decide (below).
#   2. Prime the instructions with `memory.to_prompt` so the notes are in
#      context from the first token — cheaper, and the model can't forget
#      to look. `draft_with_primed_memory` does that.
#
# Docs: https://docs.activeagents.ai/solid_agent/memory
class WriterAgent < ApplicationAgent
  include SolidAgent::HasMemory

  generate_with :openai, model: "gpt-4o-mini"

  has_memory

  def draft
    prompt(
      message: "Draft the launch post for #{params[:project].name}.",
      tools: memory_tool_definitions
    )
  end

  def draft_with_primed_memory
    prompt(
      instructions: [
        "You are a product writer.",
        memory&.to_prompt
      ].compact.join("\n\n"),
      message: "Draft the launch post for #{params[:project].name}.",
      tools: memory_tool_definitions
    )
  end

  def memory_subject
    params[:project]
  end
end

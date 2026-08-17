# frozen_string_literal: true

# First half of a hand-off: an agent that researches a project and writes
# what it learned to long-term memory.
#
# Memory is scoped to (subject record, scope name) — not to the agent class
# — so anything this agent saves is readable by any other agent working on
# the same project. `save_memory` and `recall_memory` are ordinary
# function-calling tools, so the model decides when to write and when to
# read; you only decide what the subject is.
#
# Docs: https://docs.activeagents.ai/solid_agent/memory
class ResearcherAgent < ApplicationAgent
  include SolidAgent::HasMemory

  generate_with :openai, model: "gpt-4o-mini"

  # scope: "default", class_name: "AgentMemory" unless you say otherwise.
  # Use a scope to give one subject independent memory streams
  # (has_memory scope: "competitive_research").
  has_memory

  def research
    prompt(
      message: "Research #{params[:project].name} and save what a writer would need to know.",
      tools: memory_tool_definitions
    )
  end

  # memory_subject defaults to params[:memorable], falling back to the
  # HasContext contextable. Override it when the subject is somewhere else
  # — here the project the run is about.
  def memory_subject
    params[:project]
  end
end

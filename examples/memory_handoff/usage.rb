# frozen_string_literal: true

# Memory hand-off between two agents — rails console walkthrough.
#
# Docs: https://docs.activeagents.ai/solid_agent/memory

project = Project.find(1)

# The researcher calls save_memory as it works. Each note records which
# agent class wrote it.
ResearcherAgent.with(project: project).research.generate_now

memory = AgentMemory.for(project)
memory.recall(limit: 5).map { |e| [ e.source_agent, e.category, e.content ] }
# => [["ResearcherAgent", "fact", "Ships on the 14th; pricing unchanged"], ...]

# A different agent class, later — possibly a different request, job, or
# deploy — picks the same subject up and reads those notes back.
WriterAgent.with(project: project).draft.generate_now

# Or hand the notes over without spending a tool call, by putting them in
# the instructions:
memory.to_prompt
# => "Memory notes for this subject:\n- Ships on the 14th... (ResearcherAgent)"

WriterAgent.with(project: project).draft_with_primed_memory.generate_now

# Scopes keep unrelated streams apart on the same subject:
AgentMemory.for(project, scope: "competitive_research").remember(
  "Competitor X ships a similar feature in Q3",
  source_agent: "MarketAgent",
  category: "fact"
)

# Categories filter recall; entries come back newest first.
memory.recall(category: "handoff", limit: 10)

# Curation is ordinary Active Record — nothing here is append-only by
# force, so prune when a note goes stale.
memory.entries.where(category: "task").find_each(&:destroy)

# The same tool contract is available to non-agent executors (a platform
# service, an MCP server) without including the concern:
SolidAgent::HasMemory.tool_definitions.map { |t| t[:name] }
# => ["save_memory", "recall_memory"]

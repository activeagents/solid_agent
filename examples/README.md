# SolidAgent Examples

Runnable, copy-pasteable examples for every SolidAgent concern. Each
directory mirrors the layout of a Rails app, so the files can be dropped
into `app/` as-is and the paths tell you where they belong.

Every example assumes the persistence tables and models are installed:

```bash
bundle add solid_agent
rails generate solid_agent:install
rails db:migrate
```

That generates `AgentContext`, `AgentMessage`, `AgentGeneration`,
`AgentMemory`, `AgentMemoryEntry` and `AgentRun` into `app/models/`, so they
are yours to edit — SolidAgent's concerns talk to them through a duck-typed
contract, not through hard-coded class names.

The narrative walkthrough of these examples lives at
[docs.activeagents.ai/solid_agent/examples](https://docs.activeagents.ai/solid_agent/examples).

| Example | Concerns | What it shows |
|---------|----------|---------------|
| [persistent_conversation](persistent_conversation) | `HasContext` | A support agent whose conversation survives the request, replayed from the database on every turn |
| [memory_handoff](memory_handoff) | `HasMemory` | Two agents sharing agent-curated notes about the same subject record |
| [tool_streaming](tool_streaming) | `HasTools`, `StreamsToolUpdates`, `ToolCache` | Declarative tool schemas, live "what is it doing" updates over ActionCable, cached tool results |
| [reasoning](reasoning) | `HasReasons`, `Reasonable` | Capturing extended-thinking output and persisting it on generation records |
| [run_tracking](run_tracking) | `AgentRun`, `RunFingerprint`, `ModelPricing` | Durable run records, an append-only progress stream a UI can poll, cohorts and cost |
| [manifests](manifests) | `AgentManifest` | Defining an agent in a portable `.agent.md` file and loading it as a class |

## Running the examples

The `usage.rb` file in each directory is the console script — the part you
would paste into `rails console` (or call from a controller/job) once the
agent files are in place. They are written to be read top to bottom rather
than executed blind: they hit a provider and write rows.

Prefer to try one without spending tokens? Point the agent at the mock
provider first:

```ruby
class SupportAgent < ApplicationAgent
  generate_with :mock, model: "mock-gpt-4o-mini"
end
```

Persistence, memory, runs and the tool cache all behave identically — only
the model response changes.

## Related documentation

- [SolidAgent overview](https://docs.activeagents.ai/solid_agent)
- [Conversation context](https://docs.activeagents.ai/solid_agent/context)
- [Long-term memory](https://docs.activeagents.ai/solid_agent/memory)
- [Tools, streaming and caching](https://docs.activeagents.ai/solid_agent/tools)
- [Reasoning](https://docs.activeagents.ai/solid_agent/reasoning)
- [Runs, cohorts and cost](https://docs.activeagents.ai/solid_agent/runs)
- [Agent manifests](https://docs.activeagents.ai/solid_agent/manifests)
- [`.agent.md` specification](../docs/agent-md-spec.md)

<p align="center">
  <img src="assets/solid_agent.png" alt="SolidAgent" width="200">
</p>

# SolidAgent

SolidAgent extends the [ActiveAgent](https://github.com/activeagents/activeagent) framework with database-backed persistence for everything an agent does in a Rails application: conversations, generations, tool/MCP interactions, reasoning, and long-term memory.

## Features

Agent-side concerns:

- **HasContext** - Database-backed prompt context management for maintaining conversation history and agent state, including the full tool/MCP interaction stream
- **HasMemory** - An agent-curated summary list the model reads/writes via `save_memory`/`recall_memory` function-calling tools; scoped to a subject record so agents hand off to each other through shared memory
- **HasTools** - Declarative, schema-based tool definitions compatible with LLM function-calling APIs
- **Delegates** - Agent-as-tool delegation: hand part of a job to a sub-agent under a declared input/output schema, a cost & latency budget, and a swappable backend
- **HasReasons** - Capture and inspect extended-thinking/reasoning output across a generation
- **StreamsToolUpdates** - Real-time UI feedback during tool execution via ActionCable

Model-side and standalone:

- **Reasonable** - Persist reasoning content/tokens/metadata on your generation records
- **AgentRun** - Durable run records (installed by the generator): lifecycle status, append-only progress events for live UIs, token/duration accounting, and instruction-fingerprint cohorts for comparing configuration changes
- **ToolCache** - Cache tool/MCP/service results by `(tool, normalized args)` with TTL, backed by `Rails.cache`; error results are never cached and replays are tagged `cached: true`
- **ModelPricing** - Token-count → estimated USD cost, using RubyLLM's model registry when available with a static pattern-table fallback
- **AgentManifest** - Load, validate, export, and build agent classes from portable manifests (`.agent.md`, dotprompt, CrewAI)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "solid_agent"
```

And then execute:

```bash
$ bundle install
```

## Usage

### Quick Start

Install the persistence tables and models (`AgentContext`, `AgentMessage`, `AgentGeneration`, `AgentMemory`, `AgentMemoryEntry`, `AgentRun`), then generate an agent with context support:

```bash
$ rails generate solid_agent:install
$ rails db:migrate
$ rails generate solid_agent:agent WritingAssistant --context --context_name conversation --contextual user
```

### HasContext - Persistent Conversation History

Add database-backed context management to your agents:

```ruby
class WritingAssistantAgent < ApplicationAgent
  include SolidAgent::HasContext

  has_context :conversation, contextual: :user

  def improve
    load_conversation(contextable: current_user)  # contextable is the polymorphic association
    add_conversation_user_message(params[:message])
    prompt messages: conversation_messages
  end
end
```

This generates helper methods like:
- `load_conversation(contextable:)` - Load or create a context
- `conversation_messages` - Get formatted message history
- `add_conversation_user_message(content)` - Add a user message
- `add_conversation_assistant_message(content)` - Add an AI response
- `conversation_result` - Get the last assistant message

> **Note:** contexts are persisted under `self.class.name` — agents built
> with anonymous `Class.new(...)` must define a class name or context
> creation will fail the `agent_name` presence validation.

#### Telemetry trace correlation

Every persisted generation records a `trace_id` and a provenance snapshot
(agent/prompt/context checksums). Thread a distributed trace id — for
example an `ActiveAgent::Telemetry` trace — through prompt options and it
lands on the `agent_generations` row, joining conversation records to
telemetry traces:

```ruby
def improve
  prompt_options[:trace_id] = my_telemetry_trace_id
  load_conversation(contextable: current_user)
  prompt messages: conversation_messages
end
```

Query with `AgentGeneration.with_trace(trace_id)` or
`AgentContext.with_trace(trace_id)`.

### HasTools - Declarative Tool Schemas

Define tools inline with a clean DSL:

```ruby
class ResearchAgent < ApplicationAgent
  include SolidAgent::HasTools

  tool :search do
    description "Search for information"
    parameter :query, type: :string, required: true
    parameter :limit, type: :integer, default: 10
  end

  def research
    prompt tools: tools
  end

  def search(query:, limit: 10)
    # Tool implementation
  end
end
```

Or use JSON templates in `app/views/research_agent/tools/search.json.erb`.

### Delegates - Agent-as-Tool Delegation

A tool is a Ruby method your model can call. A **delegation** is another agent your model can call — with its own instructions, templates, model, and budget. A specialist agent stays specialist, and the generalist orchestrating it never inherits its prompt.

Three declarations, each where the knowledge lives. **The contract** goes on the sub-agent, next to the action it describes:

```ruby
class SummarizerAgent < ApplicationAgent
  include SolidAgent::Delegates

  generate_with :openai, model: "gpt-4o-mini"

  delegation :summarize, description: "Condense a document into key points" do
    string  :text, required: true, description: "Full document text"
    integer :limit, description: "Maximum number of key points"

    returns do                       # optional — becomes the sub-agent's response_format
      string :summary, required: true, description: "One-paragraph summary"
      array  :points, of: :string, required: true, description: "The key points"
    end
  end

  def summarize(text:, limit: 5)
    prompt message: "Summarize in #{limit} points: #{text}"
  end
end
```

**The budget** goes at the call site, because only the caller knows what the work is worth. **The backend** goes there too, so the same sub-agent can run on different silicon in different parents:

```ruby
class ResearchAgent < ApplicationAgent
  include SolidAgent::Delegates

  generate_with :openai, model: "gpt-4o"

  delegation_budget max_calls: 8, max_duration: 60      # every delegation, together

  delegate_to SummarizerAgent, budget: { max_calls: 3, timeout: 20 }
  delegate_to FactCheckAgent, as: :verify,
              backend: { provider: :anthropic, model: "claude-haiku-4-5" }

  def research(topic:)
    prompt message: "Research #{topic}. Summarize sources before citing them.",
           tools: delegated_tools
  end
end
```

Callers never restate the sub-agent's parameters — `delegated_tools` builds them from the contract. A declared `returns` schema is parsed and checked before the caller sees it, so `summarize` hands back `{ summary: "...", points: [...] }` rather than text to re-parse.

Exhausting a budget returns a structured result the model can reason about instead of raising mid-conversation:

```ruby
{ error: "budget_exceeded", limit: "max_calls", allowed: 3, used: 3,
  message: "Delegation budget exhausted... answer with the information you already have." }
```

Cost budgets price themselves through `SolidAgent::ModelPricing`, so `max_cost: 0.25` works with no configuration. Spend is readable after a generation via `delegation_ledger`.

Because `delegate_to` defines a real instance method, a delegation is testable with no model in the loop — and `backend: :mock` runs the whole thing offline with the contract unchanged:

```ruby
agent.summarize(text: "...")   #=> { summary: "...", points: [...] }
```

See [docs/delegation.md](docs/delegation.md) for budgets, backends, `auto_delegate!`, and instrumentation.

### StreamsToolUpdates - Real-Time Feedback

Broadcast tool execution status to your UI:

```ruby
class BrowserAgent < ApplicationAgent
  include SolidAgent::HasTools
  include SolidAgent::StreamsToolUpdates

  has_tools :navigate, :click
  tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }
end
```

### HasMemory - Agent-Curated Long-Term Memory

Give an agent a durable summary list it decides when to read and write, scoped to a subject record rather than the agent class — so different agents operating on the same subject share memory, with `source_agent` provenance on every entry:

```ruby
class SupportAgent < ApplicationAgent
  include SolidAgent::HasContext
  include SolidAgent::HasMemory

  has_context contextual: :user
  has_memory # scope: "default", class_name: "AgentMemory"

  def assist
    load_context(contextable: params[:user])
    prompt messages: context_messages, tools: memory_tool_definitions
  end
end
```

The model calls `save_memory(content:, category:)` and `recall_memory(category:, limit:)` as ordinary function-calling tools. `SolidAgent::HasMemory.tool_definitions` exposes the same schemas module-level for non-agent executors (platform services, MCP servers). Inject `agent.memory.to_prompt` into instructions to prime a handoff.

### ToolCache - Cached Tool Results

```ruby
result = SolidAgent::ToolCache.fetch(tool: "fetch_url", args: { url: url }, ttl: 300) do
  expensive_call(url)
end
result[:cached] # => true on a replay
```

Error-shaped results (`{ error: ... }`) are never cached, so transient failures don't stick; cache keys are stable across argument ordering and symbol/string keys.

### AgentRun - Durable Run Records

Executors record each agent execution as an `AgentRun`: lifecycle (`start!`/`complete!`/`fail!`/`cancel!`), correlation with contexts, generations, and telemetry via `trace_id`, and an append-only progress-event stream a UI can poll mid-run:

```ruby
run = AgentRun.create!(runnable: document, agent_name: "SupportAgent", input_prompt: message)
run.record_instructions(agent.instructions) # cohort fingerprint ("calm-heron")
run.start!
run.append_event(kind: "tool", label: "fetch_url", eid: "e1", status: "started")
# ... execute ...
run.append_event(kind: "tool", label: "fetch_url", eid: "e1", status: "done", duration_ms: 120)
run.complete!(output: response.message.content, input_tokens: usage.input_tokens, output_tokens: usage.output_tokens)
```

`AgentRun#instructions_codename` names each instruction cohort deterministically (`SolidAgent::RunFingerprint`), so comparing "what changed between these two batches of runs" reads as `calm-heron` vs `misty-atoll` instead of hex digests.

### ModelPricing - Estimated Spend

```ruby
SolidAgent::ModelPricing.estimate(model: "claude-sonnet-5", input_tokens: 12_000, output_tokens: 800)
# => 0.048 (USD, estimated)
```

The generated `AgentGeneration#estimated_cost` uses this automatically. Rates come from RubyLLM's registry when that gem is present, else a static pattern table.

### Generators

```bash
# Install persistence tables + models (contexts, messages, generations, memories)
$ rails generate solid_agent:install

# Generate a new agent
$ rails generate solid_agent:agent MyAgent

# Generate with context support
$ rails generate solid_agent:agent MyAgent --context --context_name session

# Generate a tool template
$ rails generate solid_agent:tool search MyAgent --parameters query:string:required

# Generate custom-named context models
$ rails generate solid_agent:context conversation

# Add reasoning columns to a generation model
$ rails generate solid_agent:reasons AgentGeneration

# Scaffold an agent manifest (.agent.md)
$ rails generate solid_agent:manifest research
```

## Example Apps

See SolidAgent in action:

- [Fizzy](https://github.com/tonsoffun/fizzy) - AI-enhanced Kanban tracking tool with writing, research, and file analysis agents
- [Writebook](https://github.com/tonsoffun/writebook) - Collaborative writing platform with integrated AI writing assistance, research, and document analysis

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/activeagents/solid_agent.

# Agent-as-Tool Delegation

A [tool](../README.md#hastools---declarative-tool-schemas) is a Ruby method your model can call. A **delegation** is another agent your model can call.

Same mechanism, different unit of work: the callee has its own instructions, its own templates, its own model, and its own budget. That separation is the point. A specialist agent stays specialist, and the generalist orchestrating it never inherits its prompt.

```ruby
class ResearchAgent < ApplicationAgent
  include SolidAgent::Delegates

  delegate_to SummarizerAgent, budget: { max_calls: 3, timeout: 20 }

  def research(topic:)
    prompt message: "Research #{topic}", tools: delegated_tools
  end
end
```

## Three Declarations, Three Owners

| Part | Declared on | Why there |
|:-----|:------------|:----------|
| **The contract** — inputs, outputs, description | the sub-agent | It changes when the action changes. Callers never restate it. |
| **The budget** — calls, tokens, cost, latency | the call site | Only the caller knows what the work is worth. |
| **The backend** — provider, model, sampling | the call site | The same sub-agent is worth different silicon in different parents. |

Both agents include `SolidAgent::Delegates` — the one exposing work, and the one delegating it.

## Contracts

`delegation` declares one action: what it accepts, and optionally what it returns.

```ruby
class TranslatorAgent < ApplicationAgent
  include SolidAgent::Delegates

  generate_with :openai, model: "gpt-4o-mini"

  delegation :translate, description: "Translate text into a target language" do
    string :text, required: true, description: "Text to translate"
    string :locale, required: true, description: "BCP 47 target locale, e.g. pt-BR"
  end

  def translate(text:, locale:)
    prompt message: "Translate into #{locale}:\n\n#{text}"
  end
end
```

The `description` is the only thing a calling model reads before deciding whether to hand work over. Write it for someone who has never seen the code.

### Schema DSL

```ruby
delegation :search, description: "Search the product catalogue" do
  string  :query, required: true, description: "What the customer is looking for"
  integer :limit, description: "Maximum results (default 10)"
  number  :max_price, description: "Upper price bound in USD"
  boolean :in_stock_only
  string  :sort, enum: %w[relevance price rating], description: "Result ordering"

  array :categories, of: :string, description: "Restrict to these categories"

  array :filters do              # array of objects
    string :field, required: true
    string :value, required: true
  end

  object :shipping do            # nested object
    string :country, required: true, description: "ISO 3166-1 alpha-2"
  end
end
```

Any keyword beyond `required:` and `description:` lands in the JSON Schema verbatim — `enum`, `format`, `minimum`, `pattern` all work.

This is a superset of the `HasTools` `parameter` DSL: nested blocks instead of raw `items:`/`properties:` hashes, plus `returns`. If a sub-agent already declares tools with `HasTools`, the two coexist — `tools` and `delegated_tools` are separate lists you can concatenate.

### Reusing an existing schema

A contract accepts a JSON Schema hash, or any class responding to `to_json_schema`:

```ruby
delegation :create, description: "Draft a support ticket", schema: TicketForm
delegation :notify, description: "Send a notification", schema: {
  type: "object",
  properties: { channel: { type: "string" } },
  required: [ "channel" ]
}
```

### Declared outputs

`returns` declares the shape the action answers with. It becomes the sub-agent's `response_format`; the answer is parsed and its required keys checked before the caller sees it — so the calling agent receives data, not a blob of text to re-parse.

```ruby
delegation :classify, description: "Classify a support ticket by topic and urgency" do
  string :body, required: true, description: "The customer's message, verbatim"

  returns do
    string :category, required: true, enum: %w[billing bug account other]
    string :urgency, required: true, enum: %w[low normal high]
  end
end
```

The delegated call returns `{ category: "billing", urgency: "high" }`.

When the model omits a required key, the caller gets a structured `invalid_result` it can act on rather than an exception:

```ruby
{ error: "invalid_result", missing: [ "urgency" ], message: "...", content: "..." }
```

Pass `on_invalid: :raise` to the contract to fail loudly instead.

### Delegating to an agent you do not own

Declare the contract at the call site:

```ruby
delegate_to Vendor::ClassifierAgent, action: :classify,
            description: "Classify a support ticket" do
  string :body, required: true, description: "Ticket body"
end
```

This is also the escape hatch for a sub-agent that does not include `SolidAgent::Delegates`.

## Budgets

A sub-agent is a loop inside a loop. The parent model decides how often to call it, and each call spends tokens and wall-clock time nobody explicitly authorized.

```ruby
delegation_budget max_calls: 6, max_duration: 45          # every delegation, together

delegate_to TicketClassifierAgent, budget: { max_calls: 1, timeout: 10 }
delegate_to KnowledgeBaseAgent, budget: { max_calls: 3, max_tokens: 20_000 }
```

Both apply — a call has to clear the agent-wide ceiling *and* its own limit.

| Limit | Unit | Meaning |
|:------|:-----|:--------|
| `max_calls` | count | Delegated invocations |
| `max_tokens` | tokens | Cumulative tokens the sub-agent spent |
| `max_cost` | USD | Cumulative spend, priced by `ModelPricing` |
| `max_duration` | seconds | Cumulative wall-clock across delegated calls |
| `timeout` | seconds | Wall-clock ceiling for a **single** call |
| `on_exceeded` | `:stop` / `:raise` | What happens at the ceiling |
| `rates` | hash | Token prices overriding `ModelPricing` |

Budgets are scoped to one generation. The ledger lives on the agent instance, which is created fresh per generation, so there is nothing to reset and no cross-request bleed.

### Exhausting a budget

By default (`on_exceeded: :stop`) the delegation stops and the calling model is told why, in terms it can act on:

```ruby
{ error: "budget_exceeded", limit: "max_calls", allowed: 3, used: 3,
  message: "Delegation budget exhausted (max_calls: 3 of 3 used). " \
           "Do not retry this tool; answer with the information you already have." }
```

The generation continues and the model answers with what it has. A bounded answer beats an exception halfway through a conversation.

`on_exceeded: :raise` raises `SolidAgent::Delegation::BudgetExceededError`, which carries the violated limit:

```ruby
rescue SolidAgent::Delegation::BudgetExceededError => error
  error.violation.limit    #=> :max_calls
  error.violation.allowed  #=> 3
  error.violation.used     #=> 3
```

Because token spend can only be measured after a call, limits are checked *before* each call: `max_tokens: 8_000` means "stop delegating once 8,000 tokens have been spent", not "never exceed 8,000 tokens".

### Cost

Cost budgets price themselves through [`SolidAgent::ModelPricing`](../lib/solid_agent/model_pricing.rb), which resolves rates from RubyLLM's registry when available, then a static pattern table, then a blended default. `max_cost` therefore works with no configuration:

```ruby
delegate_to SummarizerAgent, budget: { max_cost: 0.05 }
```

Mock models price at $0, so a cost budget never trips accidentally in tests. Override the rate for one delegation when you pay something other than list price:

```ruby
delegate_to SummarizerAgent, budget: { max_cost: 0.05, rates: { input: 0.15, output: 0.60 } }
```

### Inspecting spend

```ruby
agent.delegation_ledger.to_h                #=> { calls: 3, tokens: 4_120, cost: 0.0009, duration: 5.2 }
agent.delegation_ledger_for(:classify).to_h #=> { calls: 1, tokens: 380, cost: 0.0001, duration: 0.7 }
```

## Swappable Backends

A sub-agent's contract is separate from what serves it:

```ruby
delegate_to SummarizerAgent, backend: { model: "gpt-4o-mini", temperature: 0 }  # same provider
delegate_to SummarizerAgent, backend: :ollama                                   # different provider
delegate_to SummarizerAgent, backend: { provider: :anthropic, model: "claude-haiku-4-5" }
```

Changing the provider rebuilds provider configuration — host, credentials, service — rather than merging a hash over the old one, so nothing leaks between vendors. It does this through a cached subclass configured by `generate_with`, the same path a hand-written agent takes; the subclass reports its parent's name, so template lookup still resolves to the original agent's views.

Backend options apply after the sub-agent's own action runs, so the call site wins — matching ActiveAgent's precedence everywhere else: **runtime > agent class > `config/active_agent.yml`**.

## Passing Tools to the Prompt

The explicit form mirrors `HasTools`:

```ruby
def research(topic:)
  prompt message: "Research #{topic}", tools: delegated_tools
end

def route(ticket:)
  prompt message: ticket, tools: delegated_tools(:classify)   # a subset
end

def triage(ticket:)
  prompt message: ticket, tools: tools + delegated_tools      # alongside HasTools
end
```

### `auto_delegate!`

If most of your actions delegate, `auto_delegate!` merges delegated tools into every action:

```ruby
class ResearchAgent < ApplicationAgent
  include SolidAgent::Delegates
  auto_delegate!

  delegate_to SummarizerAgent

  def research(topic:)
    prompt message: "Research #{topic}"      # tools merged for you
  end

  def acknowledge(ticket:)
    prompt message: ticket, delegations: false        # opt out
  end

  def route(ticket:)
    prompt message: ticket, delegations: [ :classify ] # scope
  end
end
```

This is opt-in for a reason: it works by prepending ActiveAgent's private `prepare_prompt_parameters`. It wraps the method from the outside — reading its return value rather than reaching into its body — but it is still coupled to an internal method that carries no compatibility guarantee across ActiveAgent releases. The explicit form has no such coupling. Prefer it unless the ergonomics genuinely bother you.

## Testing

Two properties make delegations easy to test.

**They are ordinary methods.** `delegate_to` defines a real instance method:

```ruby
result = ResearchAgent.new.summarize(text: "...")
```

**The backend is swappable.** Point a sub-agent at the mock provider and the contract stays exactly as production has it:

```ruby
class TestResearchAgent < ResearchAgent
  delegate_to SummarizerAgent, backend: :mock
end
```

The gem's own coverage lives in `test/integration/delegation_test.rb`, which runs against a real `ActiveAgent::Base` and drives the genuine provider tool loop. It has its own harness and rake task (`rake test:integration`) because the unit harness in `test/test_helper.rb` mocks `Rails`, which prevents `require "active_agent"` from succeeding in the same process.

## Instrumentation

Every delegated call emits `delegate.active_agent` with the agent, sub-agent, action, tool name, arguments, resolved model, duration, usage, cost and the running ledger. Refusals emit `delegation_refused.active_agent` with the violated limit.

```ruby
ActiveSupport::Notifications.subscribe("delegate.active_agent") do |*, payload|
  Rails.logger.info(
    "#{payload[:agent]} → #{payload[:delegate]}##{payload[:action]} " \
    "#{payload[:duration_ms]}ms #{payload[:usage]&.total_tokens} tokens"
  )
end
```

Delegated generations inherit the parent's trace id, so a delegation tree reads as one trace rather than scattering across unrelated ones. `Delegates` seeds it with a `before_generation` callback, since ActiveAgent otherwise mints a trace id per generation without writing it back.

## Reference

### `delegation`

| Option | Type | Purpose |
|:-------|:-----|:--------|
| `description:` | String | **Required.** What the action does, for the calling model |
| `schema:` | Hash, Class, Schema | Inputs, when not using the block DSL |
| `returns:` | Hash, Class, Schema | Declared output shape |
| `budget:` | Hash | Default budget callers inherit |
| `on_invalid:` | `:error` / `:raise` | When output misses required keys |

### `delegate_to`

| Option | Type | Purpose |
|:-------|:-----|:--------|
| `only:` / `except:` | Symbol, Array | Which of the sub-agent's contracts to expose |
| `as:` | Symbol | Rename the tool the model sees |
| `action:` | Symbol | Declare a contract here instead of on the sub-agent |
| `description:` / `schema:` / `returns:` | — | Inline contract, used with `action:` |
| `backend:` | Symbol, Hash | Provider and options this delegation runs on |
| `budget:` | Hash | Limits for this delegation |
| `params:` | Hash, Symbol, Proc | Params forwarded to the sub-agent |

```ruby
delegate_to KnowledgeBaseAgent, params: { locale: "en" }
delegate_to KnowledgeBaseAgent, params: :knowledge_base_params
delegate_to KnowledgeBaseAgent, params: -> { { account_id: params[:account_id] } }
```

## Troubleshooting

**The model never delegates.** The description is the only thing it reads. Say what the sub-agent does and when to use it. `tool_choice: "required"` forces a hand-off.

**`already responds to #name`.** The tool name collides with an existing method on the delegating agent. Rename it with `as:`.

**`does not include SolidAgent::Delegates`.** The sub-agent cannot declare contracts. Include the concern in it, or declare the contract at the call site with `action:`.

**Arguments the model invented are dropped.** Anything outside the declared schema is discarded before the sub-agent's method is called, so a hallucinated key produces a working call rather than an `ArgumentError`. If a real parameter is being dropped, it is missing from the contract.

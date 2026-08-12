# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **`SolidAgent::Delegates` — agent-as-tool delegation.** A tool is a Ruby
  method your model can call; a delegation is another agent your model can
  call, with its own instructions, templates, model and budget.
  - `delegation :action, description:` declares what a sub-agent exposes: a
    description for the calling model, a JSON Schema for its inputs (block
    DSL, a plain hash, or any class responding to `to_json_schema`), and
    optionally a `returns` schema. A declared `returns` becomes the
    sub-agent's `response_format`, and its answer is parsed and checked
    against the required keys before the caller sees it.
  - `delegate_to AgentClass` exposes those contracts as tools, with
    `only:`/`except:`/`as:` for scoping and renaming, `params:` for
    forwarding, and `action:` for declaring a contract at the call site when
    you don't own the sub-agent. Tools are passed explicitly via
    `delegated_tools`, matching `HasTools`; `auto_delegate!` opts into
    merging them onto every action.
  - Cost and latency budgets — `max_calls`, `max_tokens`, `max_cost`,
    `max_duration`, per-call `timeout` — set per delegation and/or
    agent-wide with `delegation_budget`. Exhausting one returns a structured
    result the calling model can reason about instead of raising
    mid-conversation; `on_exceeded: :raise` is available. Budgets are scoped
    to a single generation, and spend is readable via `delegation_ledger`.
    Cost is priced through the existing `SolidAgent::ModelPricing`, so
    `max_cost` works with no configuration.
  - Swappable backends: `backend: :ollama` or
    `backend: { provider: :anthropic, model: "claude-haiku-4-5" }` moves a
    delegation to different silicon without touching the sub-agent. Provider
    swaps rebuild provider configuration rather than merging over it, and
    template lookup still resolves to the original agent's views.
  - Instrumentation: `delegate.active_agent` and
    `delegation_refused.active_agent`. Delegated generations inherit the
    parent's trace id so a delegation tree reads as one trace.
  - Documented in `docs/delegation.md`.

- **Integration test harness** (`test/integration/`, `rake test:integration`)
  running against a real `ActiveAgent::Base`. The existing unit harness mocks
  `Rails`, which makes `require "active_agent"` fail in the same process, so
  the two suites run separately. `rake` runs both.

- **`CHANGELOG.md`**, which the gemspec already advertised.

### Changed

- Minimum `activeagent` raised to `>= 1.1.0`.

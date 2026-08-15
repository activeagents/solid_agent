# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-15

The first release since 0.1.1. This file arrived partway through it, so the
entries below the record extraction cover the work it did not see.

### Added

- **`SolidAgent::Records::*` — behavior for the agent-configuration records.**
  `Agent`, `AgentVersion`, `AgentTemplate`, `AgentRun` and `Ownable` ship as
  concerns; the model classes stay host-owned in `app/models`. Every
  cross-model reference resolves through `SolidAgent.agent_class` and its
  siblings at call time, so the gem never names `Agent` as a constant and never
  constantizes during load. The concerns are required eagerly, which is safe
  because nothing in them touches an ActiveRecord API until a host model
  includes one — `require "solid_agent"` in a process with no ActiveRecord
  defines the modules and loads nothing else.

  This folds the ActiveAgents platform's drifted model copies back onto the
  gem, as tracked in activeagent's `docs/framework/v2-extraction-roadmap.md`.

- **`SolidAgent.run_executor`** — the seam for executing an agent record.
  Building an agent class from stored provider/model/instructions is
  execution, which belongs to activeagent and the host, so the gem defines the
  contract and the host fills it. The default raises with instructions rather
  than returning mock data.

- **`SolidAgent.records_installed?`** — answers false both when the model
  constant is missing and when its migration has not run, so a consumer that
  must degrade (activeagent's dashboard being the motivating one) can check
  once instead of failing late.

- **Record test harness** (`test/records/`, `rake test:records`) running
  against a real ActiveRecord on sqlite `:memory:`. The unit harness mocks
  `ActiveRecord::Base`, which would put a fake under the real one, so the two
  cannot share a process. `rake` runs both.

- **`CHANGELOG.md`**, which the gemspec already advertised.

The following landed after 0.1.1 but before this file existed:

- **`AgentRun` — durable run records.** Lifecycle status
  (pending/running/complete/failed/cancelled, with `start!` / `complete!` /
  `fail!` / `cancel!`), token and duration accounting, `trace_id` correlation
  with contexts, generations and telemetry, and an append-only, byte-capped
  progress-event stream (`append_event`, pairing started/done/error by event
  id) for orchestrating and observing a long run.

- **`SolidAgent::HasMemory` — agent-curated memory.** `save_memory` and
  `recall_memory` as function-calling tool definitions with matching instance
  methods, so the agent decides when to read and write the summary list it
  carries between tools, other agents and users, including across a handoff.

- **`SolidAgent::ToolCache`, and tool round-trips in the persisted
  conversation.** `HasContext` recorded only the final assistant message, so
  the tool and MCP round-trips in the response's message stack were dropped
  and nothing downstream could show what the agent actually did. Each
  tool-result message now persists, enriched through an overridable
  `tool_invocations` hook — matched by `tool_call_id`, or by position for
  providers whose tool messages carry neither name nor id — so a row carries
  the call's arguments and timing. Tool results can be cached.

- **The tool roster offered on each generation.** `prompt_checksum` hashed the
  tool names into a digest, which proves the roster changed but cannot say
  what the agent could do; with telemetry off, a tool offered every run and
  never called left no trace at all.

- **`SolidAgent::Reasonable::Reasons`** — extended thinking traces from the
  models that emit them, stored as first-class reasoning records.

- **`SolidAgent::ModelPricing`** — per-model cost for the token counts the
  generation records already carry.

- **Cached and reasoning token usage**, alongside input and output, read
  defensively for providers that report neither, with `cache_hit?` and
  `thinking?` on the generation model.

- **Telemetry trace correlation for persisted generations.** `trace_id`
  (indexed) and `provenance` on generations, `provenance` and
  `content_checksum` on messages: the concern already populated these by
  duck-typing, but no migration template created the columns to hold them.

- **One way to load a manifest.** `SolidAgent.agent()` from any source and
  `SolidAgent.agents_from()` for a directory; `AgentManifest.load()`
  auto-detects file, URL, JSON, YAML or Hash, with explicit `from_url`,
  `from_json`, `from_yaml` and `from_hash` beside it. Manifests gained
  `#checksum`, `#provenance` and `#fingerprint`.

### Fixed

- `SolidAgent.context_class`, `message_class` and `generation_class` had no
  consumers while the shipped initializer template told hosts to set them, so
  uncommenting it did nothing. `HasContext#infer_class_names` now reads them.

- Sibling class-name derivation chained
  `delete_suffix("Context").delete_suffix("Session")`, reducing
  `SessionContext` to `""` and yielding a bare `Message`/`Generation` pair that
  collided across every context in an app. Extracted to
  `SolidAgent::ModelNaming`, which strips at most one suffix and is now the
  single place that knows the rule — the context generator derived the same
  names independently, which is how they drifted.

- `require "solid_agent"` outside Rails raised `NameError` on
  `ActiveSupport::Concern`; the gem assumed a host had already loaded
  ActiveSupport for it. It now requires the pieces it calls. The unit
  harness's hand-rolled String inflections went with it — they were defined
  *after* `require "solid_agent"` and had been shadowing ActiveSupport's, so
  the suite was exercising a toy `camelize` while production ran the real one.

### Changed

- `activemodel` is now a declared dependency. `AgentManifest` has always been
  an ActiveModel; it arrived transitively through `activerecord`, and a require
  deserves a declaration.

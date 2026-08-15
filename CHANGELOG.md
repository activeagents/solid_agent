# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

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

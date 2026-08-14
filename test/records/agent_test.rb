# frozen_string_literal: true

require_relative "records_helper"

# Host-owned models, as `rails generate solid_agent:agents` would write them.
# Named off the default constants on purpose: the gem must never reach for
# `Agent`, `AgentVersion` or `AgentRun` by hardcoded name, and the associations
# it declares must survive a host that named them something else.
SolidAgent.agent_class = "PlatformAgent"
SolidAgent.agent_version_class = "PlatformAgentVersion"
SolidAgent.agent_run_class = "PlatformAgentRun"

class PlatformAgent < ApplicationRecord
  self.table_name = "agents"

  include SolidAgent::Records::Agent
end

class PlatformAgentVersion < ApplicationRecord
  self.table_name = "agent_versions"

  include SolidAgent::Records::AgentVersion
end

class PlatformAgentRun < ApplicationRecord
  self.table_name = "agent_runs"

  belongs_to :agent, class_name: "PlatformAgent", optional: true
  enum :status, { pending: 0, running: 1, complete: 2, failed: 3 }
end

# A host whose run model implements the Records::AgentRun lifecycle. Spelled
# out here rather than by including that concern, so this suite tests the
# branch and not a sibling concern's implementation of it.
SolidAgent.agent_run_class = "LifecycleAgentRun"

class LifecycleHostAgent < ApplicationRecord
  self.table_name = "agents"

  include SolidAgent::Records::Agent
end

class LifecycleAgentRun < ApplicationRecord
  self.table_name = "agent_runs"

  class << self
    attr_accessor :calls
  end

  enum :status, { pending: 0, running: 1, complete: 2, failed: 3 }

  def finish!(**arguments)
    self.class.calls << [ :finish!, arguments ]
    update!(status: :complete, output: arguments[:output], completed_at: Time.current)
  end

  def fail!(error)
    self.class.calls << [ :fail!, error ]
    update!(status: :failed, error_message: error.message)
  end
end

# An install that generated the agent model but not the version model: the
# has_many is declared against a class name that will never resolve.
SolidAgent.agent_version_class = "NoVersionModelHere"

class HistorylessAgent < ApplicationRecord
  self.table_name = "agents"

  include SolidAgent::Records::Agent
end

SolidAgent.reset_records_configuration!

# Stands in for AgentExecutionJob without ActiveJob.
class FakeExecutionJob
  class << self
    attr_reader :enqueued

    def reset! = @enqueued = []
    def perform_later(run_id) = (@enqueued ||= []) << run_id
  end
end

class SolidAgentRecordsAgentTest < RecordsTestCase
  setup do
    SolidAgent.reset_records_configuration!
    SolidAgent.agent_class = "PlatformAgent"
    SolidAgent.agent_version_class = "PlatformAgentVersion"
    SolidAgent.agent_run_class = "PlatformAgentRun"
    SolidAgent.execution_job_class = "FakeExecutionJob"
    FakeExecutionJob.reset!
    LifecycleAgentRun.calls = []
  end

  teardown do
    SolidAgent.reset_records_configuration!
  end

  def build_agent(**overrides)
    PlatformAgent.new({
      name: "Code Reviewer",
      description: "Reviews diffs.",
      provider: "anthropic",
      model: "test-model",
      instructions: "You review code.",
      tools: %w[terminal code]
    }.merge(overrides))
  end

  def create_agent(**overrides) = build_agent(**overrides).tap(&:save!)

  # --- validations ---

  test "requires a name of at least two characters" do
    assert_includes build_agent(name: nil).tap(&:valid?).errors[:name], "can't be blank"
    assert_includes build_agent(name: "x").tap(&:valid?).errors[:name],
                    "is too short (minimum is 2 characters)"
  end

  test "rejects a name longer than 100 characters" do
    agent = build_agent(name: "a" * 101)

    refute_predicate agent, :valid?
    assert_includes agent.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "requires a provider and a model" do
    agent = build_agent(provider: nil, model: nil)

    refute_predicate agent, :valid?
    assert_includes agent.errors[:provider], "can't be blank"
    assert_includes agent.errors[:model], "can't be blank"
  end

  test "rejects slugs outside the url-safe alphabet" do
    agent = build_agent(slug: "Not A Slug")

    refute_predicate agent, :valid?
    assert_includes agent.errors[:slug], "is invalid"
  end

  test "accepts hyphens and underscores in a slug" do
    assert_predicate build_agent(slug: "code_reviewer-2"), :valid?
  end

  # --- slug generation ---

  test "generates a slug from the name" do
    assert_equal "code-reviewer", create_agent.slug
  end

  test "keeps an explicit slug" do
    assert_equal "chosen", create_agent(slug: "chosen").slug
  end

  test "suffixes colliding slugs for the same owner" do
    ada = User.create!(name: "Ada")

    assert_equal "code-reviewer", create_agent(user: ada).slug
    assert_equal "code-reviewer-1", create_agent(user: ada).slug
    assert_equal "code-reviewer-2", create_agent(user: ada).slug
  end

  test "does not suffix across owners" do
    # The unique index is (user_id, slug), so the platform model's global probe
    # was needlessly handing the second tenant a "-1".
    assert_equal "code-reviewer", create_agent(user: User.create!(name: "Ada")).slug
    assert_equal "code-reviewer", create_agent(user: User.create!(name: "Grace")).slug
  end

  test "rejects a duplicate slug within one owner" do
    ada = User.create!(name: "Ada")
    create_agent(user: ada, slug: "taken")
    duplicate = build_agent(user: ada, slug: "taken")

    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "allows the same slug for different owners" do
    create_agent(user: User.create!(name: "Ada"), slug: "shared")

    assert_predicate build_agent(user: User.create!(name: "Grace"), slug: "shared"), :valid?
  end

  test "a record does not collide with itself on update" do
    agent = create_agent

    assert agent.update(description: "Still fine.")
  end

  # --- action prompts ---

  test "action prompts must be a list of definitions" do
    agent = build_agent(action_prompts: [ "summarize" ])

    refute_predicate agent, :valid?
    assert_includes agent.errors[:action_prompts], "must be a list of action definitions"
  end

  test "action names must be snake_case" do
    agent = build_agent(action_prompts: [ { "name" => "Summarize It" } ])

    refute_predicate agent, :valid?
    assert_includes agent.errors[:action_prompts], "action name 'Summarize It' must be snake_case"
  end

  test "action names may not shadow the built-in default" do
    agent = build_agent(action_prompts: [ { "name" => "ask" } ])

    refute_predicate agent, :valid?
    assert_includes agent.errors[:action_prompts], "'ask' is the built-in default action"
  end

  test "action names must be unique" do
    agent = build_agent(action_prompts: [ { "name" => "draft" }, { "name" => "draft" } ])

    refute_predicate agent, :valid?
    assert_includes agent.errors[:action_prompts], "action names must be unique"
  end

  test "available_actions lists the default plus each named action" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])

    assert_equal %w[ask draft], agent.available_actions
  end

  test "composed_instructions_for stacks an action prompt under the base instructions" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])

    assert_equal "You review code.\n\nDraft it.", agent.composed_instructions_for("draft")
    assert_equal "You review code.", agent.composed_instructions_for("ask")
    assert_equal "You review code.", agent.composed_instructions_for(nil)
  end

  test "composed_instructions_for is nil when neither part has content" do
    agent = create_agent(instructions: nil)

    assert_nil agent.composed_instructions_for("ask")
  end

  test "action_prompt_for finds a definition by name" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])

    assert_equal "Draft it.", agent.action_prompt_for(:draft)["prompt"]
    assert_nil agent.action_prompt_for("nope")
  end

  # --- status ---

  test "models the four platform statuses" do
    assert_equal({ "draft" => 0, "active" => 1, "archived" => 2, "observed" => 3 },
                 PlatformAgent.statuses)
  end

  test "scopes separate observed agents from authored ones" do
    draft = create_agent
    live = create_agent(name: "Live", status: :active)
    seen = create_agent(name: "Seen", status: :observed)

    assert_equal [ live.id ], PlatformAgent.active_agents.pluck(:id)
    assert_equal [ seen.id ], PlatformAgent.observed_agents.pluck(:id)
    assert_equal [ draft.id, live.id ].sort, PlatformAgent.authored.pluck(:id).sort
  end

  test "by_provider filters on the provider column" do
    anthropic = create_agent
    create_agent(name: "Other", provider: "openai")

    assert_equal [ anthropic.id ], PlatformAgent.by_provider("anthropic").pluck(:id)
  end

  # --- with_tool: the one non-portable query ---

  test "with_tool finds agents by tool on a portable adapter" do
    match = create_agent
    create_agent(name: "Writer", tools: %w[edit])

    assert_equal [ match.id ], PlatformAgent.with_tool("code").pluck(:id)
  end

  test "with_tool does not match a tool name by prefix" do
    create_agent(tools: %w[research])

    assert_empty PlatformAgent.with_tool("search")
  end

  test "with_tool escapes LIKE metacharacters in the fallback" do
    create_agent(tools: %w[code])

    # Unescaped, `_` is a single-character wildcard and this would match "code".
    assert_empty PlatformAgent.with_tool("c_de")
    assert_empty PlatformAgent.with_tool("c%e")
  end

  test "with_tool uses jsonb containment on Postgres" do
    # Postgres is not available here, so the branch is asserted through the SQL
    # it builds rather than by running it. The fallback is text matching; only
    # the containment branch can use a GIN index.
    PlatformAgent.stub(:jsonb_containment?, true) do
      assert_includes PlatformAgent.with_tool("code").to_sql, "tools @> "
    end

    refute_predicate PlatformAgent, :jsonb_containment?
    refute_includes PlatformAgent.with_tool("code").to_sql, "@>"
  end

  # --- configuration_snapshot ---

  test "configuration_snapshot captures identity and versioned configuration" do
    snapshot = create_agent.configuration_snapshot

    assert_equal SolidAgent::Records::Agent::SNAPSHOT_FIELDS.map(&:to_sym).sort, snapshot.keys.sort
    assert_equal "Code Reviewer", snapshot[:name]
    assert_equal "anthropic", snapshot[:provider]
    assert_equal %w[terminal code], snapshot[:tools]
  end

  test "configuration_snapshot keeps the cosmetic columns production versions already store" do
    snapshot = create_agent(preset_type: "terminal", appearance: { "hue" => 220 }).configuration_snapshot

    assert_equal "terminal", snapshot[:preset_type]
    assert_equal({ "hue" => 220 }, snapshot[:appearance])
  end

  # --- versioning callbacks ---

  test "creating an agent writes version 1" do
    agent = create_agent

    version = agent.latest_version
    assert_equal 1, agent.version_count
    assert_equal 1, version.version_number
    assert_equal "Initial creation", version.change_summary
    assert_equal "You review code.", version.configuration_snapshot["instructions"]
  end

  test "changing a versioned field writes the next version" do
    agent = create_agent
    agent.update!(instructions: "Be terse.")

    version = agent.latest_version
    assert_equal 2, agent.version_count
    assert_equal 2, version.version_number
    assert_equal "Updated: instructions", version.change_summary
    assert_equal "Be terse.", version.configuration_snapshot["instructions"]
  end

  test "one update of several versioned fields writes one version listing them" do
    agent = create_agent
    agent.update!(instructions: "Be terse.", tools: %w[edit], model_config: { "temperature" => 0.1 })

    assert_equal 2, agent.version_count
    summary = agent.latest_version.change_summary
    assert_match(/\AUpdated: /, summary)
    assert_equal %w[instructions model_config tools], summary.sub("Updated: ", "").split(", ").sort
  end

  test "changing an unversioned field writes no version" do
    agent = create_agent

    agent.update!(name: "Renamed", description: "New copy.", provider: "openai",
                  model: "other-model", status: :active)

    assert_equal 1, agent.version_count
  end

  test "an update that changes nothing writes no version" do
    agent = create_agent
    agent.update!(instructions: "You review code.")

    assert_equal 1, agent.version_count
  end

  test "version numbers continue from the latest version" do
    agent = create_agent
    agent.update!(instructions: "Second.")
    agent.update!(tools: %w[edit])

    assert_equal [ 1, 2, 3 ], agent.agent_versions.order(:version_number).pluck(:version_number)
    assert_equal 3, agent.latest_version.version_number
  end

  test "versions belong to the agent and are destroyed with it" do
    agent = create_agent
    agent.update!(instructions: "Second.")

    assert_equal 2, PlatformAgentVersion.where(agent_id: agent.id).count
    agent.destroy!
    assert_equal 0, PlatformAgentVersion.where(agent_id: agent.id).count
  end

  # --- versioning suppression ---

  test "observed agents are not versioned on create" do
    agent = create_agent(status: :observed)

    refute_predicate agent, :versioned?
    assert_equal 0, agent.version_count
  end

  test "observed agents are not versioned when telemetry rewrites their configuration" do
    agent = create_agent(status: :observed)

    agent.update!(instructions: "Rewritten from ingest.", tools: %w[fetch])

    assert_equal 0, agent.version_count
  end

  test "an observed agent starts its history at version 1 once it is authored" do
    agent = create_agent(status: :observed)

    agent.update!(status: :draft)
    assert_equal 0, agent.version_count

    agent.update!(instructions: "Now mine.")
    assert_equal 1, agent.version_count
    assert_equal 1, agent.latest_version.version_number
  end

  test "an install without the version model keeps no history and does not raise" do
    SolidAgent.agent_version_class = "NoVersionModelHere"
    agent = HistorylessAgent.create!(name: "Solo", provider: "openai", model: "gpt-4o")

    refute_predicate agent, :versioned?
    agent.update!(instructions: "Still fine.")

    assert_equal 0, agent.version_count
    assert_nil agent.latest_version
    assert_empty agent.instructions_digest_versions
  end

  # --- restore_from_version! ---

  test "restore_from_version! restores the versioned configuration" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])
    original = agent.latest_version

    agent.update!(instructions: "Rewritten.", tools: %w[edit], action_prompts: [])
    agent.restore_from_version!(original)

    assert_equal "You review code.", agent.instructions
    assert_equal %w[terminal code], agent.tools
    assert_equal [ { "name" => "draft", "prompt" => "Draft it." } ], agent.action_prompts
  end

  test "restore_from_version! leaves identity alone" do
    agent = create_agent
    original = agent.latest_version
    agent.update!(name: "Renamed", provider: "openai", model: "other-model", instructions: "Rewritten.")

    agent.restore_from_version!(original)

    assert_equal "Renamed", agent.name
    assert_equal "openai", agent.provider
    assert_equal "other-model", agent.model
    assert_equal "You review code.", agent.instructions
  end

  test "restore_from_version! moves history forward rather than rewinding it" do
    agent = create_agent
    original = agent.latest_version
    agent.update!(instructions: "Rewritten.")

    agent.restore_from_version!(original)

    assert_equal 3, agent.version_count
    assert_equal "Updated: instructions", agent.latest_version.change_summary
    assert_equal "You review code.", agent.latest_version.configuration_snapshot["instructions"]
  end

  test "restore_from_version! resets fields a snapshot predates to their column default" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])
    ancient = PlatformAgentVersion.create!(
      agent_id: agent.id,
      version_number: 99,
      configuration_snapshot: { "instructions" => "Ancient." }
    )

    agent.restore_from_version!(ancient)

    assert_equal "Ancient.", agent.instructions
    # `nil` would break every `Array(action_prompts)` reader downstream.
    assert_equal PlatformAgent.column_defaults["action_prompts"], agent.action_prompts
  end

  test "restore_from_version! raises when the restored configuration is invalid" do
    agent = create_agent
    bad = PlatformAgentVersion.create!(
      agent_id: agent.id,
      version_number: 99,
      configuration_snapshot: { "action_prompts" => [ { "name" => "ask" } ] }
    )

    assert_raises(ActiveRecord::RecordInvalid) { agent.restore_from_version!(bad) }
  end

  # --- instructions_digest_versions ---

  test "instructions_digest_versions labels each digest with the version that introduced it" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])
    agent.update!(instructions: "Be terse.")

    map = agent.instructions_digest_versions

    assert_equal "v1", map[SolidAgent::RunFingerprint.digest("You review code.")]
    assert_equal "v1", map[SolidAgent::RunFingerprint.digest("You review code.\n\nDraft it.")]
    assert_equal "v2", map[SolidAgent::RunFingerprint.digest("Be terse.")]
  end

  test "instructions_digest_versions keeps the first version a digest appeared in" do
    agent = create_agent
    agent.update!(instructions: "Be terse.")
    agent.update!(instructions: "You review code.")

    assert_equal "v1", agent.instructions_digest_versions[SolidAgent::RunFingerprint.digest("You review code.")]
  end

  # --- telemetry correlation ---

  test "telemetry_agent_class derives an agent class name from the record" do
    assert_equal "CodeReviewerAgent", create_agent.telemetry_agent_class
    assert_equal "SupportAgent", create_agent(name: "Other", agent_class_name: "SupportAgent").telemetry_agent_class
    assert_equal "SupportAgent", create_agent(name: "Third", agent_class_name: "Support").telemetry_agent_class
  end

  # --- execute ---

  test "execute records a pending run and enqueues the configured job" do
    agent = create_agent

    run = agent.execute("Review this diff", document_id: 7)

    assert_predicate run, :persisted?
    assert_predicate run, :pending?
    assert_equal agent.id, run.agent_id
    assert_equal "Review this diff", run.input_prompt
    assert_equal({ "document_id" => 7 }, run.input_params)
    assert_match(/\A\h{8}-/, run.trace_id)
    assert_equal [ run.id ], FakeExecutionJob.enqueued
  end

  test "execute keeps a known action name and drops an unknown one" do
    agent = create_agent(action_prompts: [ { "name" => "draft", "prompt" => "Draft it." } ])

    assert_equal "draft", agent.execute("go", action: :draft).action_name
    assert_nil agent.execute("go", action: "renamed_away").action_name
  end

  test "execute resolves the job class at call time" do
    SolidAgent.execution_job_class = "NoSuchJobAnyoneDefined"
    agent = create_agent

    error = assert_raises(SolidAgent::Error) { agent.execute("go") }

    assert_match(/NoSuchJobAnyoneDefined is not defined/, error.message)
    assert_equal 0, agent.agent_runs.count
  end

  # --- test_execute ---

  test "test_execute records the executor's result on the run" do
    seen = []
    SolidAgent.run_executor = lambda do |agent_record, run|
      seen << [ agent_record, run ]
      { output: "Looks good.", metadata: { provider: agent_record.provider },
        usage: { input_tokens: 10, output_tokens: 20, total_tokens: 30 } }
    end
    agent = create_agent

    run = agent.test_execute("Review this diff")

    assert_equal [ [ agent, run ] ], seen
    assert_predicate run, :complete?
    assert_equal "Looks good.", run.output
    assert_equal({ "provider" => "anthropic" }, run.output_metadata)
    assert_equal 10, run.input_tokens
    assert_equal 20, run.output_tokens
    assert_equal 30, run.total_tokens
    assert_operator run.duration_ms, :>=, 0
    assert run.completed_at
  end

  test "test_execute accepts a string-keyed result from host code" do
    SolidAgent.run_executor = ->(_agent, _run) { { "output" => "ok", "usage" => { "total_tokens" => 5 } } }

    run = create_agent.test_execute("go")

    assert_equal "ok", run.output
    assert_equal 5, run.total_tokens
  end

  test "test_execute records a failure on the run instead of raising" do
    SolidAgent.run_executor = ->(_agent, _run) { raise ArgumentError, "provider exploded" }

    run = create_agent.test_execute("go")

    assert_predicate run, :failed?
    assert_equal "provider exploded", run.error_message
    assert_match(/agent_test\.rb/, run.error_backtrace)
    assert run.completed_at
  end

  test "test_execute records the unconfigured executor's directive on the run" do
    run = create_agent.test_execute("go")

    assert_predicate run, :failed?
    assert_match(/No SolidAgent.run_executor is configured/, run.error_message)
    assert_match(/PlatformAgent cannot be executed/, run.error_message)
  end

  test "test_execute closes the run through its own lifecycle when it has one" do
    SolidAgent.run_executor = lambda do |_agent, _run|
      { output: "Looks good.", metadata: { source: "test" }, usage: { total_tokens: 5 } }
    end
    agent = LifecycleHostAgent.create!(name: "Lifecycle", provider: "openai", model: "gpt-4o")

    run = agent.test_execute("go")

    name, arguments = LifecycleAgentRun.calls.sole
    assert_equal :finish!, name
    assert_equal "Looks good.", arguments[:output]
    assert_equal({ source: "test" }, arguments[:metadata])
    assert_equal 5, arguments[:total_tokens]
    assert_predicate run, :complete?
  end

  test "test_execute reports failures through the run's own lifecycle when it has one" do
    SolidAgent.run_executor = ->(_agent, _run) { raise ArgumentError, "provider exploded" }
    agent = LifecycleHostAgent.create!(name: "Lifecycle", provider: "openai", model: "gpt-4o")

    run = agent.test_execute("go")

    name, error = LifecycleAgentRun.calls.sole
    assert_equal :fail!, name
    assert_equal "provider exploded", error.message
    assert_predicate run, :failed?
  end

  test "runs are destroyed with the agent" do
    agent = create_agent
    agent.execute("go")

    agent.destroy!

    assert_equal 0, PlatformAgentRun.where(agent_id: agent.id).count
  end

  # --- what the gem refuses to own ---

  test "the concern ships no code generation and no closed vocabularies" do
    refute_respond_to create_agent, :to_agent_class_code
    %i[PRESET_TYPES INSTRUCTION_SETS AVAILABLE_TOOLS PROVIDERS].each do |constant|
      refute SolidAgent::Records::Agent.const_defined?(constant), "expected no #{constant}"
    end
  end

  test "the versioned field list is defined once" do
    assert_equal SolidAgent::Records::Agent::VERSIONED_FIELDS,
                 SolidAgent::Records::Agent::SNAPSHOT_FIELDS - SolidAgent::Records::Agent::DESCRIPTIVE_FIELDS
    assert_predicate SolidAgent::Records::Agent::VERSIONED_FIELDS, :frozen?
  end
end

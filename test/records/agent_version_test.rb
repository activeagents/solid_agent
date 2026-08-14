# frozen_string_literal: true

require_relative "records_helper"

# The default-named host models this suite drives — Agent, AgentVersion and
# Assistant — come from records_helper.rb. They carry the names SolidAgent
# falls back to, so the run suite needs the same constants and only one
# definition of each may exist; see the note above them there.

# A second version model under a different name, to prove the association is
# built from SolidAgent.agent_class rather than a hardcoded "Agent". The
# configuration is reset immediately afterwards: the reflection must keep the
# name it was given, and the reset must not drag it back to the default.
SolidAgent.agent_class = "Assistant"

class AssistantVersion < ApplicationRecord
  self.table_name = "agent_versions"
  include SolidAgent::Records::AgentVersion
end

SolidAgent.reset_records_configuration!

class SolidAgentRecordsAgentVersionTest < RecordsTestCase
  def setup
    @agent = Agent.create!(name: "Support", slug: "support")
  end

  # --- diff ---------------------------------------------------------------

  test "diff reports changed keys as from the other version to this one" do
    older = version(1, { "model" => "gpt-4o-mini", "provider" => "openai" })
    newer = version(2, { "model" => "gpt-4o", "provider" => "openai" })

    assert_equal({ "model" => { from: "gpt-4o-mini", to: "gpt-4o" } }, newer.diff(older))
  end

  test "diff reports a key added in this version" do
    older = version(1, { "model" => "gpt-4o" })
    newer = version(2, { "model" => "gpt-4o", "tools" => [ "search" ] })

    assert_equal({ "tools" => { from: nil, to: [ "search" ] } }, newer.diff(older))
  end

  test "diff reports a key removed in this version" do
    older = version(1, { "model" => "gpt-4o", "tools" => [ "search" ] })
    newer = version(2, { "model" => "gpt-4o" })

    assert_equal({ "tools" => { from: [ "search" ], to: nil } }, newer.diff(older))
  end

  test "diff reports additions and removals together" do
    older = version(1, { "model" => "gpt-4o", "tools" => [ "search" ] })
    newer = version(2, { "model" => "gpt-4o-mini", "mcp_servers" => [ "fs" ] })

    assert_equal(
      {
        "model" => { from: "gpt-4o", to: "gpt-4o-mini" },
        "tools" => { from: [ "search" ], to: nil },
        "mcp_servers" => { from: nil, to: [ "fs" ] }
      },
      newer.diff(older)
    )
  end

  test "diff is empty for identical snapshots" do
    older = version(1, { "model" => "gpt-4o", "tools" => [] })
    newer = version(2, { "model" => "gpt-4o", "tools" => [] })

    assert_empty newer.diff(older)
  end

  test "diff is empty without another version" do
    assert_empty version(1).diff(nil)
  end

  test "diff inverts when the arguments are swapped" do
    older = version(1, { "model" => "gpt-4o-mini" })
    newer = version(2, { "model" => "gpt-4o" })

    assert_equal({ "model" => { from: "gpt-4o", to: "gpt-4o-mini" } }, older.diff(newer))
  end

  test "diff compares symbol-keyed in-memory snapshots against persisted string keys" do
    persisted = version(1, { "model" => "gpt-4o", "provider" => "openai" })
    # What Agent#configuration_snapshot hands back before the row is written.
    unsaved = AgentVersion.new(agent: @agent, version_number: 2,
                               configuration_snapshot: { model: "gpt-4o", provider: "anthropic" })

    assert_equal({ "provider" => { from: "openai", to: "anthropic" } }, unsaved.diff(persisted))
  end

  test "diff treats a blank snapshot as no keys" do
    older = version(1, { "model" => "gpt-4o" })
    newer = AgentVersion.new(agent: @agent, version_number: 2, configuration_snapshot: nil)

    assert_equal({ "model" => { from: "gpt-4o", to: nil } }, newer.diff(older))
  end

  # --- scopes -------------------------------------------------------------

  test "recent orders by version number descending" do
    version(1)
    version(3)
    version(2)

    assert_equal [ 3, 2, 1 ], @agent.agent_versions.recent.map(&:version_number)
  end

  test "by_version selects a single version" do
    version(1)
    target = version(2)

    assert_equal [ target ], @agent.agent_versions.by_version(2).to_a
  end

  # --- history walking ----------------------------------------------------

  test "previous returns the nearest lower version" do
    first = version(1)
    version(2)
    third = version(3)

    assert_equal 2, third.previous.version_number
    assert_equal first, third.previous.previous
  end

  test "previous skips gaps in the numbering" do
    first = version(1)
    fifth = version(5)

    assert_equal first, fifth.previous
  end

  test "the first version has no previous" do
    first = version(1)
    version(2)

    assert_nil first.previous
  end

  test "next_version returns the nearest higher version" do
    first = version(1)
    version(2)
    version(3)

    assert_equal 2, first.next_version.version_number
  end

  test "the latest version has no next" do
    version(1)
    latest = version(2)

    assert_nil latest.next_version
  end

  test "history walking ignores versions belonging to another agent" do
    other = Agent.create!(name: "Sales", slug: "sales")
    other.agent_versions.create!(version_number: 1, configuration_snapshot: { "model" => "gpt-4o" })
    other.agent_versions.create!(version_number: 3, configuration_snapshot: { "model" => "gpt-4o" })

    only = version(2)

    assert_nil only.previous
    assert_nil only.next_version
    assert only.latest?
  end

  # --- boundaries ---------------------------------------------------------

  test "latest? is true only for the highest version number" do
    first = version(1)
    second = version(2)

    assert_not first.latest?
    assert second.latest?

    third = version(3)
    assert_not second.reload.latest?
    assert third.latest?
  end

  test "latest? is true for a lone version" do
    assert version(1).latest?
  end

  test "initial? is true only for version 1" do
    assert version(1).initial?
    assert_not version(2).initial?
  end

  test "initial? stays false for the oldest surviving version after pruning" do
    version(1).destroy!
    second = version(2)

    assert_nil second.previous
    assert_not second.initial?
  end

  # --- validations --------------------------------------------------------

  test "version_number is required" do
    record = AgentVersion.new(agent: @agent, version_number: nil, configuration_snapshot: { "a" => 1 })

    assert_not record.valid?
    assert_includes record.errors[:version_number], "can't be blank"
  end

  test "version_number is unique within an agent" do
    version(1)
    duplicate = AgentVersion.new(agent: @agent, version_number: 1, configuration_snapshot: { "a" => 1 })

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version_number], "has already been taken"
  end

  test "version_number may repeat across agents" do
    version(1)
    other = Agent.create!(name: "Sales", slug: "sales")

    assert other.agent_versions.build(version_number: 1, configuration_snapshot: { "a" => 1 }).valid?
  end

  test "configuration_snapshot is required and an empty hash is blank" do
    record = AgentVersion.new(agent: @agent, version_number: 1, configuration_snapshot: {})

    assert_not record.valid?
    assert_includes record.errors[:configuration_snapshot], "can't be blank"
  end

  test "agent is required" do
    record = AgentVersion.new(version_number: 1, configuration_snapshot: { "a" => 1 })

    assert_not record.valid?
    assert_includes record.errors[:agent], "must exist"
  end

  # --- the configurable seam ---------------------------------------------

  test "the agent association is named from SolidAgent.agent_class as a string" do
    assert_equal "Assistant", AssistantVersion.reflect_on_association(:agent).options[:class_name]
    assert_equal "Agent", AgentVersion.reflect_on_association(:agent).options[:class_name]
  end

  test "a differently named agent model loads through the association" do
    assistant = Assistant.create!(name: "Ops", slug: "ops")
    record = AssistantVersion.create!(agent_id: assistant.id, version_number: 1,
                                      configuration_snapshot: { "model" => "gpt-4o" })

    assert_equal assistant, record.reload.agent
    assert_instance_of Assistant, record.agent
  end

  private

  def version(number, snapshot = { "model" => "gpt-4o" })
    @agent.agent_versions.create!(version_number: number, configuration_snapshot: snapshot)
  end
end

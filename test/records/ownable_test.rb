# frozen_string_literal: true

require_relative "records_helper"

# Host-owned models, as `rails generate solid_agent:agents` would write them.
# The default mapping: an ownership column named user_id.
class OwnedAgent < ApplicationRecord
  self.table_name = "agents"

  include SolidAgent::Records::Ownable

  before_validation -> { self.slug ||= name.to_s.parameterize }, on: :create
end

# A host that owns records by something other than a user. agent_versions has
# an agent_id column, so re-owning onto it exercises a real foreign key.
class OwnedVersion < ApplicationRecord
  self.table_name = "agent_versions"

  include SolidAgent::Records::Ownable
  owned_by :agent, class_name: "OwnedAgent"
end

# A single-tenant install: agent_templates has no ownership column at all.
class UnownedTemplate < ApplicationRecord
  self.table_name = "agent_templates"

  include SolidAgent::Records::Ownable
end

# Re-owning in a subclass must not reach back into the parent.
class ReownedAgent < OwnedAgent
  owned_by :account, class_name: "Tenancy::Account", foreign_key: :user_id
end

class SolidAgentRecordsOwnableTest < RecordsTestCase
  def build_agent(**overrides)
    OwnedAgent.new({ name: "Reviewer", provider: "openai", model: "gpt-4o" }.merge(overrides))
  end

  # --- defaults ---

  test "defaults to a user association" do
    assert_equal :user, OwnedAgent.owner_association
    assert_equal "User", OwnedAgent.owner_class_name
    assert_equal "user_id", OwnedAgent.owner_foreign_key
    assert_predicate OwnedAgent, :owner_column?
  end

  test "declares the owner association by name, never as a constant" do
    reflection = OwnedAgent.reflect_on_association(:user)

    assert_equal :belongs_to, reflection.macro
    # A String here is the whole point: constantizing at include time would pin
    # a class across code reloads.
    assert_kind_of String, reflection.options[:class_name]
    assert_equal "User", reflection.options[:class_name]
    assert_equal User, reflection.klass
  end

  test "the owner is optional" do
    agent = build_agent

    assert_predicate agent, :valid?
    assert_nil agent.owner
  end

  test "does not expose an instance writer for the mapping" do
    refute_respond_to build_agent, :owner_association=
  end

  # --- owner reader and writer ---

  test "owner reads and writes through the configured association" do
    user = User.create!(name: "Ada")
    agent = build_agent

    agent.owner = user
    agent.save!

    assert_equal user, agent.owner
    assert_equal user.id, agent.user_id
    assert_equal user, agent.reload.owner
  end

  test "owner= accepts nil" do
    agent = build_agent(user: User.create!(name: "Ada"))

    agent.owner = nil

    assert_nil agent.owner
    assert_nil agent.user_id
  end

  # --- for_owner ---

  test "for_owner narrows to one owner" do
    ada = User.create!(name: "Ada")
    grace = User.create!(name: "Grace")
    hers = OwnedAgent.create!(name: "Hers", provider: "openai", model: "gpt-4o", user: ada)
    OwnedAgent.create!(name: "Theirs", provider: "openai", model: "gpt-4o", user: grace)

    assert_equal [ hers.id ], OwnedAgent.for_owner(ada).pluck(:id)
  end

  test "for_owner accepts an id as well as a record" do
    ada = User.create!(name: "Ada")
    hers = OwnedAgent.create!(name: "Hers", provider: "openai", model: "gpt-4o", user: ada)

    assert_equal [ hers.id ], OwnedAgent.for_owner(ada.id).pluck(:id)
  end

  test "for_owner(nil) finds the unowned records" do
    OwnedAgent.create!(name: "Hers", provider: "openai", model: "gpt-4o", user: User.create!(name: "Ada"))
    orphan = OwnedAgent.create!(name: "Orphan", provider: "openai", model: "gpt-4o")

    assert_equal [ orphan.id ], OwnedAgent.for_owner(nil).pluck(:id)
  end

  test "for_owner composes with other scopes" do
    ada = User.create!(name: "Ada")
    OwnedAgent.create!(name: "Hers", provider: "openai", model: "gpt-4o", user: ada)
    other = OwnedAgent.create!(name: "Other", provider: "anthropic", model: "claude", user: ada)

    assert_equal [ other.id ], OwnedAgent.for_owner(ada).where(provider: "anthropic").pluck(:id)
  end

  # --- hosts with no ownership column ---

  test "for_owner no-ops when the host stores no owner" do
    refute_predicate UnownedTemplate, :owner_column?
    template = UnownedTemplate.create!(name: "Starter", slug: "starter")

    assert_equal [ template.id ], UnownedTemplate.for_owner(User.create!(name: "Ada")).pluck(:id)
  end

  test "owner reads as nil when the host stores no owner" do
    assert_nil UnownedTemplate.create!(name: "Starter", slug: "starter").owner
  end

  # --- reconfiguration ---

  test "owned_by repoints the association, the foreign key and the scope" do
    assert_equal :agent, OwnedVersion.owner_association
    assert_equal "OwnedAgent", OwnedVersion.owner_class_name
    assert_equal "agent_id", OwnedVersion.owner_foreign_key
    assert_equal OwnedAgent, OwnedVersion.reflect_on_association(:agent).klass

    agent = OwnedAgent.create!(name: "Reviewer", provider: "openai", model: "gpt-4o")
    other = OwnedAgent.create!(name: "Other", provider: "openai", model: "gpt-4o")
    version = OwnedVersion.create!(agent_id: agent.id, version_number: 1, configuration_snapshot: { "a" => 1 })
    OwnedVersion.create!(agent_id: other.id, version_number: 1, configuration_snapshot: { "a" => 1 })

    assert_equal agent, version.owner
    assert_equal [ version.id ], OwnedVersion.for_owner(agent).pluck(:id)
  end

  test "owned_by passes options through to belongs_to" do
    reflection = ReownedAgent.reflect_on_association(:account)

    assert_equal "Tenancy::Account", reflection.options[:class_name]
    assert_equal :user_id, reflection.options[:foreign_key]
    assert reflection.options[:optional]
  end

  test "re-owning a subclass leaves its parent alone" do
    assert_equal :account, ReownedAgent.owner_association
    assert_equal :user, OwnedAgent.owner_association
    assert_equal "user_id", ReownedAgent.owner_foreign_key
  end

  test "the owner class name is never constantized until it is used" do
    # Tenancy::Account does not exist in this process, and declaring an
    # association against it must not have raised on load.
    assert_equal "Tenancy::Account", ReownedAgent.owner_class_name
    refute defined?(Tenancy)
  end
end

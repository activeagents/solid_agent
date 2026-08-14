# frozen_string_literal: true

require_relative "records_helper"

# Host-owned models, as `rails generate solid_agent:agents` would write them.
# Named off the default constants on purpose: the gem must never reach for
# `AgentTemplate` or `Agent` by hardcoded name.
class TemplateRecord < ApplicationRecord
  self.table_name = "agent_templates"

  include SolidAgent::Records::AgentTemplate
end

# Stands in for the generated Agent: slug generation and the Ownable `owner=`
# writer that maps onto whichever ownership column the host has.
class TemplatedAgent < ApplicationRecord
  self.table_name = "agents"

  belongs_to :user, optional: true
  enum :status, { draft: 0, active: 1, archived: 2 }

  before_validation :generate_slug, on: :create

  def owner=(record)
    self.user = record
  end

  def owner = user

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end

# A single-tenant install: no ownership column, so no `owner=` writer.
class UnownedAgent < TemplatedAgent
  undef_method :owner=
end

# A host that trimmed columns it does not use. Declared standalone rather than
# as a subclass so it inherits no attribute methods; `ignored_columns` is the
# only way to shrink a shared test table, and it shrinks `column_names` exactly
# the way a narrower migration would.
class NarrowAgent < ApplicationRecord
  self.table_name = "agents"
  self.ignored_columns = %w[preset_type appearance mcp_servers]

  before_validation -> { self.slug ||= name.to_s.parameterize }, on: :create

  def owner=(record)
    self.user_id = record.id
  end
end

class AlwaysInvalidAgent < TemplatedAgent
  validate { errors.add(:base, "refused") }
end

class SolidAgentRecordsAgentTemplateTest < RecordsTestCase
  setup do
    SolidAgent.reset_records_configuration!
    SolidAgent.agent_class = "TemplatedAgent"
  end

  teardown do
    SolidAgent.reset_records_configuration!
  end

  def build_template(**overrides)
    TemplateRecord.new({
      name: "Code Assistant",
      slug: "code-assistant",
      description: "Explains code.",
      provider: "anthropic",
      model: "test-model",
      instructions: "You review code.",
      preset_type: "terminal",
      appearance: { "hat" => "fedora" },
      instruction_sets: %w[ruby rails],
      tools: %w[terminal code],
      mcp_servers: { "playwright" => { "command" => "npx" } },
      model_config: { "temperature" => 0.3 }
    }.merge(overrides))
  end

  # --- validations ---

  test "requires a name" do
    template = build_template(name: nil)

    refute_predicate template, :valid?
    assert_includes template.errors[:name], "can't be blank"
  end

  test "requires a slug" do
    template = build_template(slug: nil)

    refute_predicate template, :valid?
    assert_includes template.errors[:slug], "can't be blank"
  end

  test "requires a globally unique slug" do
    build_template.save!
    duplicate = build_template(name: "Another Assistant")

    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "does not validate merchandising columns the base schema lacks" do
    assert_predicate build_template, :valid?
  end

  # --- template_configuration ---

  test "template_configuration exposes only configuration attributes" do
    config = build_template.template_configuration

    assert_equal SolidAgent::Records::AgentTemplate::CONFIGURATION_ATTRIBUTES.sort, config.keys.sort
    assert_equal "anthropic", config["provider"]
    assert_equal %w[ruby rails], config["instruction_sets"]
    refute_includes config.keys, "name"
    refute_includes config.keys, "slug"
  end

  # --- create_agent_for ---

  test "create_agent_for stamps the configuration onto a saved agent" do
    template = build_template.tap(&:save!)

    agent = template.create_agent_for(User.create!(name: "Ada"))

    assert_predicate agent, :persisted?
    assert_equal "Code Assistant", agent.name
    assert_equal "Explains code.", agent.description
    assert_equal "anthropic", agent.provider
    assert_equal "test-model", agent.model
    assert_equal "You review code.", agent.instructions
    assert_equal "terminal", agent.preset_type
    assert_equal({ "hat" => "fedora" }, agent.appearance)
    assert_equal %w[ruby rails], agent.instruction_sets
    assert_equal %w[terminal code], agent.tools
    assert_equal({ "playwright" => { "command" => "npx" } }, agent.mcp_servers)
    assert_equal({ "temperature" => 0.3 }, agent.model_config)
  end

  test "create_agent_for starts the agent as a draft" do
    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    assert_equal "draft", agent.status
  end

  test "create_agent_for overrides the name when one is given" do
    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"), name: "My Reviewer")

    assert_equal "My Reviewer", agent.name
    assert_equal "Code Assistant", TemplateRecord.first.name
  end

  test "create_agent_for falls back to the template name when the override is blank" do
    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"), name: "")

    assert_equal "Code Assistant", agent.name
  end

  test "create_agent_for assigns the owner through the Ownable writer" do
    owner = User.create!(name: "Ada")

    agent = build_template.tap(&:save!).create_agent_for(owner)

    assert_equal owner, agent.owner
    assert_equal owner.id, agent.user_id
  end

  test "create_agent_for skips ownership silently when the agent has no owner writer" do
    SolidAgent.agent_class = "UnownedAgent"

    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    assert_predicate agent, :persisted?
    assert_nil agent.user_id
  end

  test "create_agent_for copies only attributes the agent model has" do
    SolidAgent.agent_class = "NarrowAgent"

    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    assert_predicate agent, :persisted?
    assert_equal "anthropic", agent.provider
    refute_respond_to agent, :preset_type
  end

  test "create_agent_for leaves status alone when the host modeled no draft state" do
    SolidAgent.agent_class = "NarrowAgent"

    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    # NarrowAgent declares no enum, so :draft would cast to nil and violate the
    # NOT NULL constraint; the column default stands instead.
    assert_equal 0, agent.status
  end

  test "create_agent_for returns the unsaved agent with errors when it does not save" do
    SolidAgent.agent_class = "AlwaysInvalidAgent"

    agent = build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    refute_predicate agent, :persisted?
    assert_includes agent.errors[:base], "refused"
  end

  test "create_agent_for resolves the agent model at call time" do
    SolidAgent.agent_class = "NotAModelAnyoneGenerated"

    error = assert_raises(SolidAgent::Error) do
      build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))
    end

    assert_match(/NotAModelAnyoneGenerated is not defined/, error.message)
    assert_match(/rails generate solid_agent:agents/, error.message)
  end

  # --- instrumentation, in place of a usage counter ---

  test "create_agent_for instruments template.used.solid_agent" do
    template = build_template.tap(&:save!)
    owner = User.create!(name: "Ada")
    events = []
    subscription = ActiveSupport::Notifications.subscribe("template.used.solid_agent") do |*, payload|
      events << payload
    end

    agent = template.create_agent_for(owner)

    assert_equal 1, events.size
    assert_equal template, events.first[:template]
    assert_equal agent, events.first[:agent]
    assert_equal owner, events.first[:owner]
    # No merchandising columns in the base schema, so none leak into the payload.
    refute_includes events.first.keys, :category
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "create_agent_for does not instrument when the agent fails to save" do
    SolidAgent.agent_class = "AlwaysInvalidAgent"
    events = []
    subscription = ActiveSupport::Notifications.subscribe("template.used.solid_agent") do |*, payload|
      events << payload
    end

    build_template.tap(&:save!).create_agent_for(User.create!(name: "Ada"))

    assert_empty events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "the template record itself keeps no usage counter" do
    refute_includes TemplateRecord.column_names, "usage_count"
    refute_respond_to build_template, :seed_defaults!
    refute TemplateRecord.respond_to?(:seed_defaults!)
    refute defined?(SolidAgent::Records::AgentTemplate::CATEGORIES)
  end
end

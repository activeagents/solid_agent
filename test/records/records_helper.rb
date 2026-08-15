# frozen_string_literal: true

# Record harness: real ActiveRecord against an in-memory database.
#
# test/test_helper.rb mocks ActiveRecord::Base (see its "Mock ActiveRecord::Base
# for context models" section) so the unit suite runs with no database and no
# Rails. That mock is fine for concerns that only read attributes, but the
# record concerns in lib/solid_agent/records/ are ActiveRecord code —
# validations, enums, callbacks, scopes, associations — and mocking them would
# only test the mock.
#
# So this harness boots a real ActiveRecord on sqlite3 :memory: and defines the
# schema the generator emits. It cannot share a process with test/test_helper.rb
# (whose mock `Rails` constant makes `require "active_agent"` raise), which is
# why records/ has its own rake task alongside integration/.
#
# Postgres-only behavior — jsonb containment, partial unique indexes — is
# documented in each concern and is NOT covered here; sqlite is the portable
# floor, not the target.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "active_support/all"
require "active_support/test_case"
require "active_model"
require "active_record"
require "minitest/autorun"

require "solid_agent"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

# Host applications own their models; the gem ships behavior. These stand in for
# what `rails generate solid_agent:agents` writes into app/models.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

module RecordsSchema
  # Mirrors the generator's migration templates. Kept here rather than loaded
  # from them so a schema change has to be made deliberately in two places —
  # the templates are user-facing output and should not be executed as code.
  def self.load!
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define do
      create_table :users, force: true do |t|
        t.string :name
        t.timestamps
      end

      create_table :agents, force: true do |t|
        t.string  :name, null: false
        t.text    :description
        t.string  :slug, null: false
        t.string  :agent_class_name
        t.string  :action_name
        t.json    :action_prompts, default: {}
        t.string  :provider, default: "openai"
        t.string  :model, default: "gpt-4o-mini"
        t.string  :service_name
        t.text    :instructions
        t.string  :preset_type
        t.json    :appearance, default: {}
        t.json    :instruction_sets, default: []
        t.json    :tools, default: []
        t.json    :mcp_servers, default: []
        t.json    :model_config, default: {}
        t.json    :response_format, default: {}
        t.integer :status, default: 0, null: false
        t.string  :source
        t.datetime :first_observed_at
        t.datetime :last_observed_at
        t.references :user
        t.timestamps
      end
      add_index :agents, [ :user_id, :slug ], unique: true

      create_table :agent_versions, force: true do |t|
        t.references :agent, null: false
        t.integer :version_number, null: false, default: 1
        t.string  :change_summary
        t.json    :configuration_snapshot, null: false, default: {}
        t.string  :created_by
        t.timestamps
      end
      add_index :agent_versions, [ :agent_id, :version_number ], unique: true

      create_table :agent_templates, force: true do |t|
        t.string :name, null: false
        t.string :slug, null: false
        t.text   :description
        t.string :provider, default: "openai"
        t.string :model, default: "gpt-4o-mini"
        t.text   :instructions
        t.string :preset_type
        t.json   :appearance, default: {}
        t.json   :instruction_sets, default: []
        t.json   :tools, default: []
        t.json   :mcp_servers, default: {}
        t.json   :model_config, default: {}
        t.timestamps
      end
      add_index :agent_templates, :slug, unique: true

      create_table :agent_runs, force: true do |t|
        t.references :agent
        t.references :runnable, polymorphic: true
        t.string  :agent_name
        t.string  :action_name
        t.string  :trace_id
        t.integer :status, default: 0, null: false
        t.text    :input_prompt
        t.json    :input_params, default: {}
        t.text    :output
        t.json    :output_metadata, default: {}
        t.text    :error_message
        t.text    :error_backtrace
        t.json    :events, default: []
        t.string  :instructions_digest
        t.integer :input_tokens
        t.integer :output_tokens
        t.integer :total_tokens
        t.integer :duration_ms
        t.datetime :started_at
        t.datetime :completed_at
        t.timestamps
      end
      add_index :agent_runs, :trace_id
    end
  end
end

RecordsSchema.load!

class User < ApplicationRecord
  has_many :agents, dependent: :destroy
end

# The default-named host models.
#
# +Agent+, +AgentVersion+ and +AgentRun+ are the constants SolidAgent falls
# back to when a host configures nothing, so more than one test file needs
# them by those exact names — and Ruby would not complain about it. Two files
# each opening `class Agent < ApplicationRecord` merge into a single class
# whose associations depend on which file `Dir[]` happened to load first, and
# whose behavior changes when either file is edited. One definition here is
# what makes that impossible.
#
# Models a single suite needs alone — PlatformAgent, TemplateRecord,
# OwnedAgent, the two legacy run schemas — still belong in that suite's file.
# Only the shared defaults live here.
#
# Agent is deliberately a plain model: Records::Agent is exercised through
# agent_test.rb's differently-named PlatformAgent, and the version and run
# suites want a host agent that carries no gem behavior of its own.
class Agent < ApplicationRecord
  has_many :agent_versions, dependent: :destroy
  has_many :agent_runs, dependent: :destroy
end

class AgentVersion < ApplicationRecord
  include SolidAgent::Records::AgentVersion
end

class AgentRun < ApplicationRecord
  include SolidAgent::Records::AgentRun
end

# The same agent under a second name, so each suite can prove its association
# is built from SolidAgent.agent_class rather than a hardcoded "Agent". The
# version and run halves of that pair stay with their own suites, since each
# has to be defined while agent_class points here.
class Assistant < ApplicationRecord
  self.table_name = "agents"
end

# Base class for record-concern tests: wraps each test in a transaction so
# fixtures never leak between them.
class RecordsTestCase < ActiveSupport::TestCase
  def run(*args, &block)
    result = nil
    ActiveRecord::Base.transaction do
      result = super
      raise ActiveRecord::Rollback
    end
    result
  end
end

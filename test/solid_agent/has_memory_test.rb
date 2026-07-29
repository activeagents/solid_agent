# frozen_string_literal: true

# test_helper stubs ActiveSupport::Concern and loads the full gem against
# it — do NOT require the real active_support here: its Concern would
# override the stub's append_features mid-suite and break every include.
require "test_helper"

class SolidAgent::HasMemoryTest < Minitest::Test
  FakeEntry = Struct.new(:id, :content, :category, :source_agent, :created_at)

  # Implements the memory-model contract HasMemory duck-types against.
  class FakeMemory
    class << self
      attr_accessor :instances

      def for(memorable, scope:)
        self.instances ||= {}
        self.instances[[ memorable, scope ]] ||= new(memorable, scope)
      end
    end

    attr_reader :memorable, :scope, :entries

    def initialize(memorable, scope)
      @memorable = memorable
      @scope = scope
      @entries = []
    end

    def remember(content, source_agent: nil, category: nil)
      entry = FakeEntry.new(@entries.size + 1, content, category, source_agent, Time.now)
      @entries << entry
      entry
    end

    def recall(limit: 20, category: nil)
      list = @entries.reverse
      list = list.select { |e| e.category == category } if category
      list.first(limit || 20)
    end
  end

  class FakeAgent
    include SolidAgent::HasMemory
    has_memory class_name: "SolidAgent::HasMemoryTest::FakeMemory"

    attr_reader :params

    def initialize(params = {})
      @params = params
    end
  end

  def setup
    FakeMemory.instances = {}
  end

  def test_tool_definitions_expose_save_and_recall
    names = SolidAgent::HasMemory.tool_definitions.map { |d| d[:name] }
    assert_equal %w[save_memory recall_memory], names

    agent = FakeAgent.new(memorable: "subject-1")
    assert_equal names, agent.memory_tool_definitions.map { |d| d[:name] }
  end

  def test_save_and_recall_roundtrip
    agent = FakeAgent.new(memorable: "subject-1")

    saved = agent.save_memory(content: "User prefers terse answers", category: "fact")
    assert saved[:saved]

    recalled = agent.recall_memory
    assert_equal 1, recalled[:count]
    assert_equal "User prefers terse answers", recalled[:entries].first[:content]
    assert_equal "SolidAgent::HasMemoryTest::FakeAgent", recalled[:entries].first[:source_agent]
  end

  def test_memory_is_shared_across_agent_classes_for_handoff
    other_agent_class = Class.new do
      include SolidAgent::HasMemory
      has_memory class_name: "SolidAgent::HasMemoryTest::FakeMemory"
      def self.name = "SecondAgent"
      attr_reader :params
      def initialize(params) = @params = params
    end

    FakeAgent.new(memorable: "shared-subject").save_memory(content: "Research done: use approach B")
    recalled = other_agent_class.new({ memorable: "shared-subject" }).recall_memory

    assert_equal 1, recalled[:count]
    assert_equal "Research done: use approach B", recalled[:entries].first[:content]
  end

  def test_category_filter_passes_through
    agent = FakeAgent.new(memorable: "s")
    agent.save_memory(content: "a fact", category: "fact")
    agent.save_memory(content: "a task", category: "task")

    recalled = agent.recall_memory(category: "task")
    assert_equal [ "a task" ], recalled[:entries].map { |e| e[:content] }
  end

  def test_errors_without_a_subject
    agent = FakeAgent.new({})

    assert_equal({ error: "No memory subject available" }, agent.save_memory(content: "x"))
    assert_equal({ error: "No memory subject available" }, agent.recall_memory)
  end
end

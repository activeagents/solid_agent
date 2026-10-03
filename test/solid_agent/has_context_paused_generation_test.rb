# frozen_string_literal: true

require "test_helper"

# A generation that pauses for user input returns a response answering
# `awaiting_input?`; the generation that resumes it replays the restored
# conversation as its prompt messages. Neither may leave rows on the context
# that misrepresent the conversation. The fakes stand in for a framework
# release that has the pause, so nothing here depends on one.
class HasContextPausedGenerationTest < Minitest::Test
  Message = Struct.new(:role, :content, :name, :tool_call_id)

  # A response from a framework release without the pause: no `awaiting_input?`.
  class FakeResponse
    attr_reader :messages

    def initialize(messages)
      @messages = messages
    end

    def message
      messages.last
    end
  end

  class PausableResponse < FakeResponse
    def initialize(messages, awaiting_input:)
      super(messages)
      @awaiting_input = awaiting_input
    end

    def awaiting_input?
      @awaiting_input
    end
  end

  # Persisted rows live in one array so ordering across user, tool and
  # assistant rows is observable, as it is on a real messages table.
  class FakeMessages
    def initialize(rows, visible:)
      @rows = rows
      @visible = visible
    end

    def create!(**attributes)
      @rows << attributes
      attributes
    end

    def exists?(role:, tool_call_id:)
      @visible && @rows.any? { |row| row[:role] == role && row[:tool_call_id] == tool_call_id }
    end

    def size
      @rows.size
    end

    def last
      nil
    end
  end

  class FakeContext
    attr_reader :rows, :generations

    # `rows_visible_to_exists: false` models a messages scope that cannot see
    # rows written earlier in the same persistence pass.
    def initialize(rows: [], rows_visible_to_exists: true)
      @rows = rows
      @generations = []
      @visible = rows_visible_to_exists
    end

    def id
      1
    end

    def messages
      FakeMessages.new(@rows, visible: @visible)
    end

    def add_tool_message(tool_call_id:, tool_name:, result:, arguments: nil, duration_ms: nil)
      @rows << { role: "tool", tool_call_id: tool_call_id, tool_name: tool_name, content: result }
    end

    def record_generation!(response)
      @generations << response
      @rows << { role: "assistant", content: response.message.content }
    end
  end

  def setup
    Object.const_set(:AgentContext, SolidAgentTestHelpers::MockAgentContext) unless defined?(AgentContext)
    Object.const_set(:AgentMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(AgentMessage)
    Object.const_set(:AgentGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(AgentGeneration)

    @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
      has_context
    end
  end

  def teardown
    Object.send(:remove_const, :AgentContext) if defined?(AgentContext)
    Object.send(:remove_const, :AgentMessage) if defined?(AgentMessage)
    Object.send(:remove_const, :AgentGeneration) if defined?(AgentGeneration)
  end

  def build_agent(context, messages: [], agent_class: @agent_class)
    agent = agent_class.new
    agent.context = context
    agent.prompt_options = { messages: messages }
    agent
  end

  # Prompt messages are hashes, as the framework's `prompt(messages:)` takes
  # them; response stacks hold message objects.
  def prompt_message(role, content)
    { role: role, content: content }
  end

  def user(content)
    Message.new("user", content)
  end

  def assistant(content)
    Message.new("assistant", content)
  end

  def tool(tool_call_id, content, name: "lookup")
    Message.new("tool", content, name, tool_call_id)
  end

  def paused_response(messages)
    PausableResponse.new(messages, awaiting_input: true)
  end

  # Runs one generation the way the framework orders the callbacks: the
  # around_generation callback wraps the provider call, and after_prompt
  # callbacks run once the provider returns.
  def generate(agent, response)
    agent.run_around_generation do
      agent.run_after_prompt_callbacks
      response
    end
  end

  # === resuming_generation? ===

  def test_resuming_generation_is_false_by_default
    refute build_agent(FakeContext.new).send(:resuming_generation?)
  end

  def test_resuming_generation_is_true_when_the_agent_sets_it
    agent = build_agent(FakeContext.new)
    agent.instance_exec { self.resuming_generation = true }

    assert_equal true, agent.send(:resuming_generation?)
  end

  def test_resuming_generation_follows_the_framework_flag
    resuming_class = Class.new(@agent_class) { def resuming? = :yes }
    idle_class = Class.new(@agent_class) { def resuming? = false }

    assert_equal true, build_agent(FakeContext.new, agent_class: resuming_class).send(:resuming_generation?)
    assert_equal false, build_agent(FakeContext.new, agent_class: idle_class).send(:resuming_generation?)
  end

  # A public method on an agent is one of its actions, and the action list
  # feeds the framework's release digest.
  def test_resuming_generation_methods_are_not_public
    public_methods = @agent_class.public_instance_methods

    refute_includes public_methods, :resuming_generation?
    refute_includes public_methods, :resuming_generation=
  end

  # === Prompt persistence ===

  def test_prompt_is_persisted_for_a_fresh_generation
    context = FakeContext.new
    build_agent(context, messages: [ prompt_message("user", "Book a table for two") ]).send(:persist_prompt_to_context)

    assert_equal [ { role: "user", content: "Book a table for two" } ], context.rows
  end

  def test_prompt_is_not_persisted_when_the_host_marks_a_resume
    context = FakeContext.new
    agent = build_agent(context, messages: [
      prompt_message("user", "Book a table for two"),
      { role: "tool", tool_call_id: "call_1", content: "{\"slots\":[\"19:00\"]}" }
    ])
    agent.send(:resuming_generation=, true)

    agent.send(:persist_prompt_to_context)

    assert_empty context.rows
  end

  def test_prompt_is_not_persisted_when_the_framework_reports_a_resume
    context = FakeContext.new
    resuming_class = Class.new(@agent_class) { def resuming? = true }
    agent = build_agent(context, messages: [ prompt_message("assistant", [ { type: "tool_use", id: "call_1" } ]) ],
                        agent_class: resuming_class)

    agent.send(:persist_prompt_to_context)

    assert_empty context.rows
  end

  # === Generation persistence ===

  def test_a_paused_generation_persists_its_prompt_but_not_its_response
    context = FakeContext.new
    agent = build_agent(context, messages: [ prompt_message("user", "Book a table for two") ])

    generate(agent, paused_response([ user("Book a table for two"), tool("call_1", "{\"slots\":[\"19:00\"]}") ]))

    assert_equal [ { role: "user", content: "Book a table for two" } ], context.rows
    assert_empty context.generations
  end

  def test_a_paused_response_is_returned_but_not_persisted
    context = FakeContext.new
    response = paused_response([
      user("Book a table for two"),
      assistant("Which evening works for you?"),
      tool("call_1", "{\"slots\":[\"19:00\"]}")
    ])
    agent = build_agent(context)

    result = agent.send(:capture_and_persist_generation) { response }

    assert_same response, result
    assert_same response, agent.generation_response
    assert_empty context.generations, "a paused response must not be recorded as a generation"
    assert_empty context.rows, "a paused response must not leave assistant or tool rows"
  end

  def test_a_response_that_is_not_awaiting_input_is_persisted
    context = FakeContext.new
    response = PausableResponse.new([ tool("call_1", "42"), assistant("It is 42.") ], awaiting_input: false)

    build_agent(context).send(:capture_and_persist_generation) { response }

    assert_equal [ response ], context.generations
    assert_equal [ "tool", "assistant" ], context.rows.map { |row| row[:role] }
  end

  def test_a_response_without_awaiting_input_is_persisted
    context = FakeContext.new
    response = FakeResponse.new([ assistant("Done.") ])

    build_agent(context).send(:capture_and_persist_generation) { response }

    assert_equal [ response ], context.generations
  end

  # === Tool message dedupe ===

  def test_a_tool_call_id_repeated_in_one_stack_is_persisted_once
    context = FakeContext.new(rows_visible_to_exists: false)
    response = FakeResponse.new([
      tool("call_1", "{\"slots\":[\"19:00\"]}"),
      tool("call_1", "{\"slots\":[\"19:00\"]}"),
      assistant("Booked.")
    ])

    build_agent(context).send(:capture_and_persist_generation) { response }

    assert_equal [ "call_1" ], context.rows.select { |row| row[:role] == "tool" }.map { |row| row[:tool_call_id] }
  end

  # === Pause, then resume ===

  def test_pause_then_resume_persists_the_user_turn_tool_results_and_answer_once
    context = FakeContext.new(rows: [
      { role: "user", content: "What's on tonight?" },
      { role: "tool", tool_call_id: "call_0", tool_name: "lookup", content: "[]" },
      { role: "assistant", content: "Nothing is on tonight." }
    ])
    history = [ user("What's on tonight?"), tool("call_0", "[]"), assistant("Nothing is on tonight.") ]
    slots = "{\"slots\":[\"19:00\",\"20:30\"]}"

    # The paused run: call_1 completed, call_2 asked the user which evening.
    pausing_agent = build_agent(context, messages: [ prompt_message("user", "Book a table for two") ])
    paused = paused_response(history + [
      user("Book a table for two"),
      assistant("Checking availability."),
      tool("call_1", slots)
    ])
    generate(pausing_agent, paused)

    # The resumed run replays the restored conversation through the pending
    # tool-call turn, dispatches call_2 again with the answer, and finishes.
    resuming_agent = build_agent(context, messages: [
      prompt_message("user", "Book a table for two"),
      prompt_message("assistant", [ { type: "tool_use", id: "call_1" }, { type: "tool_use", id: "call_2" } ]),
      { role: "tool", tool_call_id: "call_1", content: slots }
    ])
    resuming_agent.send(:resuming_generation=, true)
    finished = FakeResponse.new(history + [
      user("Book a table for two"),
      assistant("Checking availability."),
      tool("call_1", slots),
      tool("call_2", "{\"evening\":\"Friday\"}", name: "ask_user"),
      assistant("Booked Friday at 19:00.")
    ])
    generate(resuming_agent, finished)

    assert_equal [
      { role: "user", content: "Book a table for two" },
      { role: "tool", tool_call_id: "call_1", tool_name: "lookup", content: slots },
      { role: "tool", tool_call_id: "call_2", tool_name: "ask_user", content: "{\"evening\":\"Friday\"}" },
      { role: "assistant", content: "Booked Friday at 19:00." }
    ], context.rows.drop(3)
    assert_equal [ finished ], context.generations
  end
end

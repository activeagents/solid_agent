# frozen_string_literal: true

require "test_helper"

class HasContextTest < Minitest::Test
  def setup
    # Define mock models for context persistence
    Object.const_set(:AgentContext, SolidAgentTestHelpers::MockAgentContext) unless defined?(AgentContext)
    Object.const_set(:AgentMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(AgentMessage)
    Object.const_set(:AgentGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(AgentGeneration)

    # Create a fresh agent class for each test
    @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
    end
  end

  def teardown
    # Clean up constants
    Object.send(:remove_const, :AgentContext) if defined?(AgentContext)
    Object.send(:remove_const, :AgentMessage) if defined?(AgentMessage)
    Object.send(:remove_const, :AgentGeneration) if defined?(AgentGeneration)
  end

  # === has_context DSL tests ===

  def test_has_context_sets_default_config
    @agent_class.has_context

    assert_equal "AgentContext", @agent_class.context_config[:context_class]
    assert_equal "AgentMessage", @agent_class.context_config[:message_class]
    assert_equal "AgentGeneration", @agent_class.context_config[:generation_class]
    assert_equal true, @agent_class.context_config[:auto_save]
  end

  def test_has_context_accepts_custom_model_classes
    @agent_class.has_context(
      context_class: "Conversation",
      message_class: "ConversationMessage",
      generation_class: "ConversationGeneration"
    )

    assert_equal "Conversation", @agent_class.context_config[:context_class]
    assert_equal "ConversationMessage", @agent_class.context_config[:message_class]
    assert_equal "ConversationGeneration", @agent_class.context_config[:generation_class]
  end

  def test_has_context_can_disable_auto_save
    @agent_class.has_context(auto_save: false)

    assert_equal false, @agent_class.context_config[:auto_save]
  end

  def test_has_context_registers_callbacks_when_auto_save_enabled
    @agent_class.has_context(auto_save: true)

    assert_includes @agent_class.after_prompt_callbacks, :persist_prompt_to_context
    assert_includes @agent_class.around_generation_callbacks, :capture_and_persist_generation
  end

  def test_has_context_does_not_register_callbacks_when_auto_save_disabled
    @agent_class.has_context(auto_save: false)

    refute_includes @agent_class.after_prompt_callbacks || [], :persist_prompt_to_context
    refute_includes @agent_class.around_generation_callbacks || [], :capture_and_persist_generation
  end

  # === Context loading tests ===

  def test_load_context_by_id
    @agent_class.has_context
    agent = @agent_class.new

    context = agent.load_context(context_id: 123)

    assert_equal 123, context.id
  end

  def test_load_context_with_contextable_creates_new_context
    @agent_class.has_context
    agent = @agent_class.new

    mock_user = Object.new
    context = agent.load_context(contextable: mock_user)

    assert_equal mock_user, context.contextable
    assert_equal @agent_class.name, context.agent_name
    assert_equal "test_action", context.action_name
  end

  def test_load_context_without_params_creates_new_context
    @agent_class.has_context
    agent = @agent_class.new
    agent.prompt_options = { instructions: "Be helpful" }

    context = agent.load_context

    assert_equal @agent_class.name, context.agent_name
    assert_equal "Be helpful", context.instructions
  end

  def test_create_context_always_creates_new
    @agent_class.has_context
    agent = @agent_class.new

    mock_page = Object.new
    context = agent.create_context(
      contextable: mock_page,
      input_params: { task: "improve", content: "Hello" }
    )

    assert_equal mock_page, context.contextable
    assert_equal({ task: "improve", content: "Hello" }, context.input_params)
  end

  # === Message management tests ===

  def test_add_message_requires_context
    @agent_class.has_context
    agent = @agent_class.new

    error = assert_raises(SolidAgent::Error) do
      agent.add_message(role: "user", content: "Hello")
    end

    assert_match(/No context loaded/, error.message)
  end

  def test_add_message_creates_message_on_context
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    # Mock the messages association
    agent.context.define_singleton_method(:messages) do
      @messages_proxy ||= Object.new.tap do |proxy|
        proxy.define_singleton_method(:create!) do |attrs|
          SolidAgentTestHelpers::MockAgentMessage.new(attrs)
        end
      end
    end

    message = agent.add_message(role: "user", content: "Hello world")

    assert_equal "user", message.role
    assert_equal "Hello world", message.content
  end

  def test_add_user_message_convenience_method
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    agent.context.define_singleton_method(:messages) do
      @messages_proxy ||= Object.new.tap do |proxy|
        proxy.define_singleton_method(:create!) do |attrs|
          SolidAgentTestHelpers::MockAgentMessage.new(attrs)
        end
      end
    end

    message = agent.add_user_message("Test content")

    assert_equal "user", message.role
    assert_equal "Test content", message.content
  end

  def test_add_assistant_message_convenience_method
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    agent.context.define_singleton_method(:messages) do
      @messages_proxy ||= Object.new.tap do |proxy|
        proxy.define_singleton_method(:create!) do |attrs|
          SolidAgentTestHelpers::MockAgentMessage.new(attrs)
        end
      end
    end

    message = agent.add_assistant_message("AI response")

    assert_equal "assistant", message.role
    assert_equal "AI response", message.content
  end

  # === Context messages tests ===

  def test_context_messages_returns_empty_array_without_context
    @agent_class.has_context
    agent = @agent_class.new

    assert_equal [], agent.context_messages
  end

  def test_context_messages_returns_formatted_messages
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    mock_messages = [
      SolidAgentTestHelpers::MockAgentMessage.new(role: "user", content: "Hello"),
      SolidAgentTestHelpers::MockAgentMessage.new(role: "assistant", content: "Hi there")
    ]

    agent.context.define_singleton_method(:messages) do
      mock_messages
    end

    messages = agent.context_messages

    assert_equal 2, messages.length
    assert_equal({ role: "user", content: "Hello" }, messages[0])
    assert_equal({ role: "assistant", content: "Hi there" }, messages[1])
  end

  def test_with_context_messages_sets_prompt_messages
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    mock_messages = [
      SolidAgentTestHelpers::MockAgentMessage.new(role: "user", content: "Hello")
    ]

    agent.context.define_singleton_method(:messages) do
      mock_messages
    end

    agent.with_context_messages

    assert_equal [{ role: "user", content: "Hello" }], agent.prompt_options[:messages]
  end

  # === Model class accessors ===

  def test_context_class_constantizes_string
    @agent_class.has_context(context_class: "AgentContext")
    agent = @agent_class.new

    assert_equal AgentContext, agent.context_class
  end

  def test_message_class_constantizes_string
    @agent_class.has_context(message_class: "AgentMessage")
    agent = @agent_class.new

    assert_equal AgentMessage, agent.message_class
  end

  def test_generation_class_constantizes_string
    @agent_class.has_context(generation_class: "AgentGeneration")
    agent = @agent_class.new

    assert_equal AgentGeneration, agent.generation_class
  end

  # === Auto-save callback tests ===

  def test_persist_prompt_to_context_saves_rendered_message
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context
    agent.prompt_options = { messages: [{ content: "Improve this text" }] }

    saved_messages = []
    agent.context.define_singleton_method(:messages) do
      @messages_proxy ||= Object.new.tap do |proxy|
        proxy.define_singleton_method(:create!) do |attrs|
          saved_messages << attrs
          SolidAgentTestHelpers::MockAgentMessage.new(attrs)
        end
      end
    end

    agent.send(:persist_prompt_to_context)

    assert_equal 1, saved_messages.length
    assert_equal "user", saved_messages.first[:role]
    assert_equal "Improve this text", saved_messages.first[:content]
  end

  def test_capture_and_persist_generation_stores_response
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    mock_response = SolidAgentTestHelpers::MockGenerationResponse.new(content: "Improved text here")

    result = agent.send(:capture_and_persist_generation) { mock_response }

    assert_equal mock_response, result
    assert_equal mock_response, agent.generation_response
    assert_includes agent.context.generations, mock_response
  end
end

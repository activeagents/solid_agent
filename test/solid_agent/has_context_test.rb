# frozen_string_literal: true

require "test_helper"

class HasContextTest < Minitest::Test
  def setup
    # Define mock models for context persistence
    Object.const_set(:AgentContext, SolidAgentTestHelpers::MockAgentContext) unless defined?(AgentContext)
    Object.const_set(:AgentMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(AgentMessage)
    Object.const_set(:AgentGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(AgentGeneration)

    # Define mock models for named contexts
    Object.const_set(:Conversation, SolidAgentTestHelpers::MockAgentContext) unless defined?(Conversation)
    Object.const_set(:ConversationMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(ConversationMessage)
    Object.const_set(:ConversationGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(ConversationGeneration)
    Object.const_set(:ResearchSession, SolidAgentTestHelpers::MockAgentContext) unless defined?(ResearchSession)
    Object.const_set(:ResearchSessionMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(ResearchSessionMessage)
    Object.const_set(:ResearchSessionGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(ResearchSessionGeneration)

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
    Object.send(:remove_const, :Conversation) if defined?(Conversation)
    Object.send(:remove_const, :ConversationMessage) if defined?(ConversationMessage)
    Object.send(:remove_const, :ConversationGeneration) if defined?(ConversationGeneration)
    Object.send(:remove_const, :ResearchSession) if defined?(ResearchSession)
    Object.send(:remove_const, :ResearchSessionMessage) if defined?(ResearchSessionMessage)
    Object.send(:remove_const, :ResearchSessionGeneration) if defined?(ResearchSessionGeneration)
  end

  # === has_context DSL tests ===

  def test_has_context_sets_default_config
    @agent_class.has_context

    config = @agent_class._context_configs[:context]
    assert_equal "AgentContext", config[:context_class]
    assert_equal "AgentMessage", config[:message_class]
    assert_equal "AgentGeneration", config[:generation_class]
    assert_equal true, config[:auto_save]
  end

  def test_has_context_accepts_custom_model_classes
    @agent_class.has_context(:conversation,
      class_name: "Conversation",
      message_class: "ConversationMessage",
      generation_class: "ConversationGeneration"
    )

    config = @agent_class._context_configs[:conversation]
    assert_equal "Conversation", config[:context_class]
    assert_equal "ConversationMessage", config[:message_class]
    assert_equal "ConversationGeneration", config[:generation_class]
  end

  def test_has_context_can_disable_auto_save
    @agent_class.has_context(auto_save: false)

    config = @agent_class._context_configs[:context]
    assert_equal false, config[:auto_save]
  end

  # === Named context tests (association-style) ===

  def test_has_context_with_name_infers_class_names
    @agent_class.has_context :conversation

    config = @agent_class._context_configs[:conversation]
    assert_equal "Conversation", config[:context_class]
    assert_equal "ConversationMessage", config[:message_class]
    assert_equal "ConversationGeneration", config[:generation_class]
  end

  def test_has_context_creates_named_accessor
    @agent_class.has_context :conversation

    agent = @agent_class.new
    assert agent.respond_to?(:conversation)
    assert agent.respond_to?(:conversation=)
  end

  def test_has_context_creates_named_methods
    @agent_class.has_context :conversation

    agent = @agent_class.new
    assert agent.respond_to?(:load_conversation)
    assert agent.respond_to?(:create_conversation)
    assert agent.respond_to?(:conversation_messages)
    assert agent.respond_to?(:with_conversation_messages)
    assert agent.respond_to?(:add_conversation_message)
    assert agent.respond_to?(:add_conversation_user_message)
    assert agent.respond_to?(:add_conversation_assistant_message)
  end

  def test_has_context_with_explicit_class_name
    @agent_class.has_context :session, class_name: "ChatSession"

    config = @agent_class._context_configs[:session]
    assert_equal "ChatSession", config[:context_class]
    assert_equal "ChatMessage", config[:message_class]
    assert_equal "ChatGeneration", config[:generation_class]
  end

  def test_multiple_contexts_in_same_agent
    # Create a fresh class for this test to avoid issues with class_attribute inheritance
    multi_context_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
    end

    multi_context_class.has_context :conversation
    multi_context_class.has_context :analysis, class_name: "AnalysisContext"

    configs = multi_context_class._context_configs

    assert_equal 2, configs.size
    assert configs.key?(:conversation)
    assert configs.key?(:analysis)

    agent = multi_context_class.new
    assert agent.respond_to?(:conversation)
    assert agent.respond_to?(:analysis)
    assert agent.respond_to?(:load_conversation)
    assert agent.respond_to?(:load_analysis)
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
    @agent_class.has_context  # Uses default "AgentContext"
    agent = @agent_class.new

    assert_equal AgentContext, agent.context_class
  end

  def test_message_class_constantizes_string
    @agent_class.has_context  # Uses default "AgentMessage"
    agent = @agent_class.new

    assert_equal AgentMessage, agent.message_class
  end

  def test_generation_class_constantizes_string
    @agent_class.has_context  # Uses default "AgentGeneration"
    agent = @agent_class.new

    assert_equal AgentGeneration, agent.generation_class
  end

  # === Result extraction tests ===

  def test_context_result_returns_last_assistant_message
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    # Add some messages
    user_msg = SolidAgentTestHelpers::MockAgentMessage.new(role: "user", content: "Hello")
    asst_msg1 = SolidAgentTestHelpers::MockAgentMessage.new(role: "assistant", content: "First response")
    asst_msg2 = SolidAgentTestHelpers::MockAgentMessage.new(role: "assistant", content: "Final answer")

    agent.context.messages = [user_msg, asst_msg1, asst_msg2]

    assert_equal "Final answer", agent.context_result
  end

  def test_context_result_returns_nil_without_assistant_messages
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    user_msg = SolidAgentTestHelpers::MockAgentMessage.new(role: "user", content: "Hello")
    agent.context.messages = [user_msg]

    assert_nil agent.context_result
  end

  def test_named_context_result_method
    @agent_class.has_context :conversation
    agent = @agent_class.new

    assert agent.respond_to?(:conversation_result)
  end

  def test_context_summary_returns_structured_data
    @agent_class.has_context
    agent = @agent_class.new
    agent.create_context

    asst_msg = SolidAgentTestHelpers::MockAgentMessage.new(role: "assistant", content: "The answer is 42")
    agent.context.messages = [asst_msg]
    agent.context.id = 123

    summary = agent.context_summary

    assert_equal 123, summary[:id]
    assert_equal "The answer is 42", summary[:result]
    assert_equal 1, summary[:message_count]
  end

  def test_named_context_summary_method
    @agent_class.has_context :research_session
    agent = @agent_class.new

    assert agent.respond_to?(:research_session_summary)
    assert agent.respond_to?(:research_session_result)
    assert agent.respond_to?(:research_session_last_generation)
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

  # === Auto-context tests ===

  def test_has_context_with_contextable_stores_config
    @agent_class.has_context :conversation, contextable: :user

    config = @agent_class._context_configs[:conversation]
    assert_equal :user, config[:contextable]
  end

  def test_has_context_with_contextable_false_stores_config
    @agent_class.has_context :conversation, contextable: false

    config = @agent_class._context_configs[:conversation]
    assert_equal false, config[:contextable]
  end

  def test_has_context_registers_ensure_callback_by_default
    @agent_class.has_context :conversation

    assert_includes @agent_class.after_prompt_callbacks, :ensure_conversation_exists
  end

  def test_has_context_does_not_register_ensure_callback_when_contextable_false
    @agent_class.has_context :conversation, contextable: false

    refute_includes @agent_class.after_prompt_callbacks || [], :ensure_conversation_exists
  end

  def test_ensure_context_exists_creates_context_automatically
    @agent_class.has_context :conversation

    agent = @agent_class.new
    assert_nil agent.conversation

    agent.send(:ensure_conversation_exists)

    refute_nil agent.conversation
    assert_equal @agent_class.name, agent.conversation.agent_name
  end

  def test_ensure_context_exists_with_contextable_param
    @agent_class.has_context :conversation, contextable: :user

    agent = @agent_class.new
    mock_user = Object.new
    agent.params = { user: mock_user }

    agent.send(:ensure_conversation_exists)

    refute_nil agent.conversation
    assert_equal mock_user, agent.conversation.contextable
  end

  def test_ensure_context_exists_does_not_recreate_existing_context
    @agent_class.has_context :conversation

    agent = @agent_class.new
    agent.create_conversation
    original_context = agent.conversation

    agent.send(:ensure_conversation_exists)

    assert_same original_context, agent.conversation
  end

  def test_auto_context_with_named_context_uses_correct_param
    @agent_class.has_context :research_session, contextable: :project

    agent = @agent_class.new
    mock_project = Object.new
    agent.params = { project: mock_project }

    agent.send(:ensure_research_session_exists)

    assert_equal mock_project, agent.research_session.contextable
  end

  def test_auto_context_without_contextable_creates_anonymous_context
    @agent_class.has_context :conversation  # No contextable specified, defaults to nil

    agent = @agent_class.new
    agent.params = {}

    agent.send(:ensure_conversation_exists)

    refute_nil agent.conversation
    assert_nil agent.conversation.contextable
  end
end

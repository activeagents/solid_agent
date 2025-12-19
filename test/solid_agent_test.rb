# frozen_string_literal: true

require "test_helper"

class SolidAgentTest < Minitest::Test
  def test_version_number
    refute_nil SolidAgent::VERSION
  end

  def test_error_class_exists
    assert_kind_of Class, SolidAgent::Error
    assert SolidAgent::Error < StandardError
  end
end

# Integration tests showing concerns working together
class SolidAgentIntegrationTest < Minitest::Test
  def setup
    # Define mock models
    Object.const_set(:AgentContext, SolidAgentTestHelpers::MockAgentContext) unless defined?(AgentContext)
    Object.const_set(:AgentMessage, SolidAgentTestHelpers::MockAgentMessage) unless defined?(AgentMessage)
    Object.const_set(:AgentGeneration, SolidAgentTestHelpers::MockAgentGeneration) unless defined?(AgentGeneration)

    ActionCable.server.clear!
  end

  def teardown
    Object.send(:remove_const, :AgentContext) if defined?(AgentContext)
    Object.send(:remove_const, :AgentMessage) if defined?(AgentMessage)
    Object.send(:remove_const, :AgentGeneration) if defined?(AgentGeneration)
    ActionCable.server.clear!
  end

  # Simulates WritingAssistantAgent pattern from fizzy/writebook
  def test_writing_assistant_agent_pattern
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext

      has_context

      attr_accessor :task, :content

      def improve
        @task = "improve the writing quality"
        setup_context_and_prompt
      end

      def summarize
        @task = "create a concise summary"
        setup_context_and_prompt
      end

      private

      def setup_context_and_prompt
        create_context(
          contextable: params[:contextable],
          input_params: { task: @task, content: params[:content] }
        )
        prompt
      end
    end

    agent = agent_class.new
    agent.params = { content: "Some text to improve", contextable: Object.new }

    agent.improve

    refute_nil agent.context
    assert_equal agent_class.name, agent.context.agent_name
    assert_equal({ task: "improve the writing quality", content: "Some text to improve" }, agent.context.input_params)
  end

  # Simulates ResearchAssistantAgent pattern from writebook
  def test_research_assistant_agent_pattern
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
      include SolidAgent::HasTools
      include SolidAgent::StreamsToolUpdates

      has_context
      has_tools :navigate, :extract_text

      tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }
      tool_description :extract_text, "Reading page content..."

      def navigate(url:)
        { success: true, url: url }
      end

      def extract_text(selector: "body")
        { success: true, text: "Content" }
      end

      def research
        @topic = params[:topic]

        create_context(
          contextable: params[:contextable],
          input_params: { topic: @topic }
        )

        prompt(tools: tools, tool_choice: "auto")
      end
    end

    agent = agent_class.new
    agent.params = {
      topic: "Ruby on Rails",
      contextable: Object.new,
      stream_id: "research_stream_123"
    }

    # Mock render_to_string for tool loading
    agent.define_singleton_method(:render_to_string) do |options|
      tool_name = options[:template].split("/").last
      {
        type: "function",
        name: tool_name,
        description: "#{tool_name} tool",
        parameters: { type: "object", properties: {}, required: [] }
      }.to_json
    end

    agent.research

    # Verify context was created
    refute_nil agent.context
    assert_equal({ topic: "Ruby on Rails" }, agent.context.input_params)

    # Verify tools are available
    tools = agent.tools
    assert_equal 2, tools.length

    # Verify prompt was called with tools
    assert_equal tools, agent.prompt_options[:tools]
    assert_equal "auto", agent.prompt_options[:tool_choice]

    # Simulate tool execution with broadcasting
    agent.navigate(url: "https://rubyonrails.org")

    broadcasts = ActionCable.server.broadcasts
    assert_equal 1, broadcasts.length
    assert_equal "research_stream_123", broadcasts.first[:channel]
    assert_match(/Visiting/, broadcasts.first[:data][:tool_status][:description])
  end

  # Test agent inheriting from another agent with concerns
  def test_concern_inheritance
    base_agent = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext
      include SolidAgent::HasTools

      has_context
    end

    child_agent = Class.new(base_agent) do
      tool :custom_tool do
        description "A custom tool"
        parameter :input, type: :string, required: true
      end
    end

    agent = child_agent.new
    tools = agent.tools

    assert_equal 1, tools.length
    assert_equal "custom_tool", tools.first[:name]
  end

  # Test FileAnalysisAgent pattern from fizzy
  def test_file_analysis_agent_pattern
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasContext

      has_context

      attr_accessor :message, :image_data

      def analyze
        @message = params[:message] || "Analyze this content"

        create_context(
          contextable: params[:contextable],
          input_params: {
            message: @message,
            has_image: params[:image_data].present?
          }
        )

        prompt(
          message: @message,
          image_data: params[:image_data]
        )
      end
    end

    agent = agent_class.new
    agent.params = {
      message: "Describe this image",
      image_data: "data:image/png;base64,abc123",
      contextable: Object.new
    }

    agent.analyze

    refute_nil agent.context
    assert_equal({ message: "Describe this image", has_image: true }, agent.context.input_params)
    assert_equal "Describe this image", agent.prompt_options[:message]
    assert_equal "data:image/png;base64,abc123", agent.prompt_options[:image_data]
  end
end

# frozen_string_literal: true

require "test_helper"
require "set"

class StreamsToolUpdatesTest < Minitest::Test
  def setup
    # Clear any previous broadcasts
    ActionCable.server.clear!

    # Create a fresh agent class for each test
    @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::StreamsToolUpdates

      # Define some tool methods to test wrapping
      def navigate(url:)
        { success: true, url: url }
      end

      def search(query:)
        { success: true, query: query }
      end

      def extract_text(selector: "body")
        { success: true, text: "Sample text" }
      end

      def custom_tool(input:)
        { success: true, input: input }
      end
    end
  end

  def teardown
    ActionCable.server.clear!
  end

  # === tool_description DSL tests ===

  def test_tool_description_with_static_string
    @agent_class.tool_description :extract_text, "Reading page content..."

    assert_equal "Reading page content...", @agent_class._tool_descriptions[:extract_text]
  end

  def test_tool_description_with_proc
    @agent_class.tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }

    description_proc = @agent_class._tool_descriptions[:navigate]
    assert_equal "Visiting https://example.com...", description_proc.call(url: "https://example.com")
  end

  def test_tool_description_adds_to_wrapped_tools
    @agent_class.tool_description :navigate, "Navigating..."

    assert_includes @agent_class._wrapped_tools, :navigate
  end

  def test_tool_description_does_not_double_wrap
    @agent_class.tool_description :navigate, "First description"
    @agent_class.tool_description :navigate, "Updated description"

    # Should only be wrapped once
    assert_equal 1, @agent_class._wrapped_tools.count(:navigate)
    # Description should be updated
    assert_equal "Updated description", @agent_class._tool_descriptions[:navigate]
  end

  # === Broadcasting tests ===

  def test_broadcasts_tool_status_with_stream_id
    @agent_class.tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }

    agent = @agent_class.new
    agent.params = { stream_id: "stream_123" }

    agent.navigate(url: "https://example.com")

    broadcasts = ActionCable.server.broadcasts
    assert_equal 1, broadcasts.length
    assert_equal "stream_123", broadcasts.first[:channel]
    assert_equal "navigate", broadcasts.first[:data][:tool_status][:name]
    assert_equal "Visiting https://example.com...", broadcasts.first[:data][:tool_status][:description]
    assert broadcasts.first[:data][:tool_status][:timestamp]
  end

  def test_does_not_broadcast_without_stream_id
    @agent_class.tool_description :navigate, "Navigating..."

    agent = @agent_class.new
    agent.params = {}

    agent.navigate(url: "https://example.com")

    assert_empty ActionCable.server.broadcasts
  end

  def test_tool_still_executes_after_broadcast
    @agent_class.tool_description :search, "Searching..."

    agent = @agent_class.new
    agent.params = { stream_id: "stream_123" }

    result = agent.search(query: "test query")

    assert_equal({ success: true, query: "test query" }, result)
  end

  # === Default description tests ===

  def test_default_description_for_navigate_with_url
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :navigate, { url: "https://example.com" })

    # truncate_url extracts host when URL is short enough
    assert_match(/Visiting.*example\.com/, description)
  end

  def test_default_description_for_navigate_without_url
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :navigate, {})

    assert_equal "Navigating to page...", description
  end

  def test_default_description_for_click_with_text
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :click, { text: "Submit" })

    assert_equal "Clicking 'Submit'...", description
  end

  def test_default_description_for_click_without_text
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :click, {})

    assert_equal "Clicking element...", description
  end

  def test_default_description_for_fill_form
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :fill_form, { field: "username" })

    assert_equal "Filling in username...", description
  end

  def test_default_description_for_extract_text
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :extract_text, {})

    assert_equal "Reading page content...", description
  end

  def test_default_description_for_extract_main_content
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :extract_main_content, {})

    assert_equal "Reading page content...", description
  end

  def test_default_description_for_search_with_query
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :search, { query: "Ruby gems" })

    assert_equal "Searching for 'Ruby gems'...", description
  end

  def test_default_description_for_read_file
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :read_file, { path: "/path/to/document.txt" })

    assert_equal "Reading document.txt...", description
  end

  def test_default_description_for_unknown_tool
    agent = @agent_class.new

    description = agent.send(:default_tool_description, :custom_tool, {})

    assert_equal "Performing custom tool...", description
  end

  # === URL truncation tests ===

  def test_truncate_url_short_url
    agent = @agent_class.new

    truncated = agent.send(:truncate_url, "https://example.com")

    assert_equal "https://example.com", truncated
  end

  def test_truncate_url_long_url
    agent = @agent_class.new
    long_url = "https://example.com/very/long/path/that/exceeds/the/maximum/allowed/length/for/display"

    truncated = agent.send(:truncate_url, long_url, max_length: 30)

    assert truncated.length <= 33  # max_length + "..."
    assert truncated.end_with?("...")
  end

  def test_truncate_url_invalid_url
    agent = @agent_class.new

    truncated = agent.send(:truncate_url, "not a valid url but very long text that should be truncated", max_length: 20)

    assert truncated.length <= 24  # Includes "..."
  end

  # === Real-world usage pattern tests (based on ResearchAssistantAgent) ===

  def test_research_agent_style_tool_descriptions
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::StreamsToolUpdates

      def navigate(url:); end
      def click(selector: nil, text: nil); end
      def fill_form(field:, value:); end
      def extract_text(selector: "body"); end
      def extract_main_content; end
      def extract_links(selector: "body", limit: 10); end
      def page_info; end
      def go_back; end

      # Custom tool descriptions for UI feedback during execution
      tool_description :navigate, ->(args) { "Visiting #{args[:url] || 'page'}..." }
      tool_description :click, ->(args) { args[:text] ? "Clicking '#{args[:text]}'..." : "Clicking element..." }
      tool_description :fill_form, ->(args) { "Filling in #{args[:field] || 'form field'}..." }
      tool_description :extract_text, "Reading page content..."
      tool_description :extract_main_content, "Extracting main content..."
      tool_description :extract_links, "Finding links on page..."
      tool_description :page_info, "Analyzing page structure..."
      tool_description :go_back, "Going back to previous page..."
    end

    assert_equal 8, agent_class._tool_descriptions.length
    assert_equal 8, agent_class._wrapped_tools.length

    # Test that static descriptions work
    assert_equal "Reading page content...", agent_class._tool_descriptions[:extract_text]

    # Test that dynamic descriptions work
    navigate_desc = agent_class._tool_descriptions[:navigate]
    assert_equal "Visiting https://test.com...", navigate_desc.call(url: "https://test.com")
  end

  def test_tool_broadcasts_on_research_agent_flow
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::StreamsToolUpdates

      def navigate(url:)
        { success: true, current_url: url }
      end

      def extract_main_content
        { success: true, content: "Page content" }
      end

      tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }
      tool_description :extract_main_content, "Extracting main content..."
    end

    agent = agent_class.new
    agent.params = { stream_id: "research_session_456" }

    # Simulate a research flow
    agent.navigate(url: "https://wikipedia.org")
    agent.extract_main_content

    broadcasts = ActionCable.server.broadcasts
    assert_equal 2, broadcasts.length

    assert_equal "navigate", broadcasts[0][:data][:tool_status][:name]
    assert_equal "Visiting https://wikipedia.org...", broadcasts[0][:data][:tool_status][:description]

    assert_equal "extract_main_content", broadcasts[1][:data][:tool_status][:name]
    assert_equal "Extracting main content...", broadcasts[1][:data][:tool_status][:description]
  end

  # === tool_description_for priority tests ===

  def test_custom_proc_description_takes_priority
    @agent_class.tool_description :navigate, ->(args) { "Custom: #{args[:url]}" }

    agent = @agent_class.new
    description = agent.send(:tool_description_for, :navigate, { url: "test.com" })

    assert_equal "Custom: test.com", description
  end

  def test_custom_string_description_takes_priority
    @agent_class.tool_description :extract_text, "Custom reading..."

    agent = @agent_class.new
    description = agent.send(:tool_description_for, :extract_text, {})

    assert_equal "Custom reading...", description
  end

  def test_falls_back_to_default_without_custom_description
    agent = @agent_class.new
    description = agent.send(:tool_description_for, :search, { query: "test" })

    assert_equal "Searching for 'test'...", description
  end
end

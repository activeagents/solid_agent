# frozen_string_literal: true

require "test_helper"
require "json"

class HasToolsTest < Minitest::Test
  def setup
    # Create a fresh agent class for each test
    @agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasTools
    end
  end

  # === has_tools DSL tests ===

  def test_has_tools_without_args_enables_auto_discover
    @agent_class.has_tools

    assert_equal true, @agent_class._tools_auto_discover
  end

  def test_has_tools_with_args_sets_explicit_tool_names
    @agent_class.has_tools :navigate, :click, :fill_form

    assert_equal [:navigate, :click, :fill_form], @agent_class._tool_names
    assert_equal false, @agent_class._tools_auto_discover
  end

  def test_has_tools_converts_strings_to_symbols
    @agent_class.has_tools "search", "fetch"

    assert_equal [:search, :fetch], @agent_class._tool_names
  end

  # === Inline tool definition tests ===

  def test_tool_dsl_defines_basic_tool
    @agent_class.tool :search do
      description "Search for documents"
    end

    schema = @agent_class._inline_tools[:search]

    assert_equal "function", schema[:type]
    assert_equal "search", schema[:name]
    assert_equal "Search for documents", schema[:description]
  end

  def test_tool_dsl_with_required_parameter
    @agent_class.tool :search do
      description "Search for documents"
      parameter :query, type: :string, required: true, description: "Search query"
    end

    schema = @agent_class._inline_tools[:search]

    assert_equal "string", schema[:parameters][:properties]["query"][:type]
    assert_equal "Search query", schema[:parameters][:properties]["query"][:description]
    assert_includes schema[:parameters][:required], "query"
  end

  def test_tool_dsl_with_optional_parameter
    @agent_class.tool :search do
      description "Search"
      parameter :limit, type: :integer, default: 10
    end

    schema = @agent_class._inline_tools[:search]

    assert_equal "integer", schema[:parameters][:properties]["limit"][:type]
    assert_equal 10, schema[:parameters][:properties]["limit"][:default]
    refute_includes schema[:parameters][:required], "limit"
  end

  def test_tool_dsl_with_enum_parameter
    @agent_class.tool :format_output do
      description "Format output"
      parameter :format, type: :string, enum: %w[json xml csv]
    end

    schema = @agent_class._inline_tools[:format_output]

    assert_equal %w[json xml csv], schema[:parameters][:properties]["format"][:enum]
  end

  def test_tool_dsl_with_array_parameter
    @agent_class.tool :tag_documents do
      description "Tag documents"
      parameter :tags, type: :array, items: { type: :string }
    end

    schema = @agent_class._inline_tools[:tag_documents]

    assert_equal "array", schema[:parameters][:properties]["tags"][:type]
    assert_equal({ type: :string }, schema[:parameters][:properties]["tags"][:items])
  end

  def test_tool_dsl_with_multiple_parameters
    @agent_class.tool :navigate do
      description "Navigate to a URL"
      parameter :url, type: :string, required: true, description: "URL to visit"
      parameter :wait_for, type: :string, description: "Element to wait for"
      parameter :timeout, type: :integer, default: 30
    end

    schema = @agent_class._inline_tools[:navigate]

    assert_equal 3, schema[:parameters][:properties].length
    assert_equal ["url"], schema[:parameters][:required]
  end

  # === Tool schema generation tests ===

  def test_to_schema_produces_openai_format
    builder = SolidAgent::HasTools::ToolBuilder.new(:test_tool)
    builder.description("A test tool")
    builder.parameter(:input, type: :string, required: true)

    schema = builder.to_schema

    expected = {
      type: "function",
      name: "test_tool",
      description: "A test tool",
      parameters: {
        type: "object",
        properties: {
          "input" => { type: "string" }
        },
        required: ["input"]
      }
    }

    assert_equal expected, schema
  end

  # === tools method tests ===

  def test_tools_returns_inline_tools
    @agent_class.tool :search do
      description "Search"
      parameter :query, type: :string, required: true
    end

    @agent_class.tool :fetch do
      description "Fetch"
      parameter :url, type: :string, required: true
    end

    agent = @agent_class.new
    tools = agent.tools

    assert_equal 2, tools.length
    assert_equal "search", tools[0][:name]
    assert_equal "fetch", tools[1][:name]
  end

  def test_tools_caches_result
    @agent_class.tool :search do
      description "Search"
    end

    agent = @agent_class.new
    tools1 = agent.tools
    tools2 = agent.tools

    assert_same tools1, tools2
  end

  def test_reload_tools_clears_cache
    @agent_class.tool :search do
      description "Search"
    end

    agent = @agent_class.new
    tools1 = agent.tools
    agent.reload_tools!
    tools2 = agent.tools

    refute_same tools1, tools2
    assert_equal tools1, tools2
  end

  # === Template loading tests ===

  def test_load_tool_schema_parses_json
    @agent_class.has_tools :test_tool

    agent = @agent_class.new

    # Mock render_to_string to return valid JSON
    agent.define_singleton_method(:render_to_string) do |options|
      {
        type: "function",
        name: "test_tool",
        description: "A test tool",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string" }
          },
          required: ["query"]
        }
      }.to_json
    end

    schema = agent.send(:load_tool_schema, :test_tool)

    assert_equal "function", schema[:type]
    assert_equal "test_tool", schema[:name]
  end

  def test_load_tool_schema_raises_on_invalid_json
    @agent_class.has_tools :bad_tool

    agent = @agent_class.new
    agent.define_singleton_method(:render_to_string) { |_| "not valid json" }

    assert_raises(JSON::ParserError) do
      agent.send(:load_tool_schema, :bad_tool)
    end
  end

  # === Mixed tools tests (like ResearchAssistantAgent) ===

  def test_mixed_explicit_and_inline_tools
    @agent_class.has_tools :navigate, :click

    @agent_class.tool :custom_action do
      description "A custom action"
      parameter :input, type: :string, required: true
    end

    agent = @agent_class.new

    # Mock template loading
    agent.define_singleton_method(:render_to_string) do |options|
      tool_name = options[:template].split("/").last
      {
        type: "function",
        name: tool_name,
        description: "#{tool_name} tool",
        parameters: { type: "object", properties: {}, required: [] }
      }.to_json
    end

    tools = agent.tools

    assert_equal 3, tools.length
    tool_names = tools.map { |t| t[:name] }
    assert_includes tool_names, "navigate"
    assert_includes tool_names, "click"
    assert_includes tool_names, "custom_action"
  end

  # === Real-world usage pattern tests (based on fizzy/writebook) ===

  def test_research_agent_style_tool_setup
    # Simulates ResearchAssistantAgent pattern
    agent_class = Class.new(SolidAgentTestHelpers::MockBaseAgent) do
      include SolidAgent::HasTools

      has_tools :navigate, :click, :fill_form, :extract_text, :extract_main_content, :extract_links, :page_info, :go_back
    end

    assert_equal 8, agent_class._tool_names.length
    assert_includes agent_class._tool_names, :navigate
    assert_includes agent_class._tool_names, :extract_main_content
  end

  def test_agent_with_prompt_tools_option
    @agent_class.tool :search do
      description "Search the web"
      parameter :query, type: :string, required: true
    end

    agent = @agent_class.new
    tools = agent.tools

    # Simulates: prompt(tools: tools, tool_choice: "auto")
    agent.prompt(tools: tools, tool_choice: "auto")

    assert_equal tools, agent.prompt_options[:tools]
    assert_equal "auto", agent.prompt_options[:tool_choice]
  end
end

# frozen_string_literal: true

require_relative "browser_session"

module ActivePrompt
  # BrowserAgent is a specialized agent for browser automation using Playwright MCP.
  #
  # It provides an agent that can navigate web pages, interact with elements,
  # and handle authentication workflows by pausing for user intervention.
  #
  # @example Creating a browser agent
  #   class MyBrowserAgent < ActivePrompt::BrowserAgent
  #     def perform_task
  #       navigate_to("https://example.com")
  #       click_element("button[type=submit]")
  #       extract_content("h1")
  #     end
  #   end
  #
  # @example Using with simple instructions
  #   agent = ActivePrompt::BrowserAgent.new(
  #     instructions: "Navigate to github.com and find the trending repositories"
  #   )
  #   agent.execute
  #
  module BrowserAgent
    extend ActiveSupport::Concern

    include BrowserSession

    PLAYWRIGHT_TOOLS = %w[
      browser_navigate
      browser_snapshot
      browser_click
      browser_type
      browser_fill_form
      browser_take_screenshot
      browser_press_key
      browser_evaluate
      browser_wait_for
      browser_console_messages
      browser_network_requests
      browser_tabs
      browser_hover
      browser_select_option
      browser_drag
      browser_handle_dialog
      browser_file_upload
      browser_close
      browser_navigate_back
      browser_resize
      browser_install
    ].freeze

    included do
      include SolidAgent::HasContext if defined?(SolidAgent::HasContext)
      include SolidAgent::HasTools if defined?(SolidAgent::HasTools)
      include SolidAgent::HasReasons if defined?(SolidAgent::HasReasons)
      include SolidAgent::StreamsToolUpdates if defined?(SolidAgent::StreamsToolUpdates)

      # Set up context for fragment persistence
      if respond_to?(:has_context)
        has_context :browser_session, contextual: false
      end

      # Set up reasoning capture
      if respond_to?(:has_reasons)
        has_reasons auto_capture: true, persist: true
      end

      # Register tool descriptions for streaming updates
      if respond_to?(:tool_description)
        tool_description :browser_navigate, ->(args) { "Navigating to #{truncate_url(args[:url])}" }
        tool_description :browser_snapshot, "Getting page snapshot"
        tool_description :browser_click, ->(args) { "Clicking #{args[:element] || 'element'}" }
        tool_description :browser_type, ->(args) { "Typing text into #{args[:element] || 'field'}" }
        tool_description :browser_fill_form, "Filling form fields"
        tool_description :browser_take_screenshot, "Taking screenshot"
        tool_description :browser_wait_for, "Waiting for element"
        tool_description :browser_evaluate, "Evaluating JavaScript"
      end

      attr_accessor :mcp_client, :session, :task_instructions
    end

    class_methods do
      # Create and execute a browser agent with simple instructions
      #
      # @param instructions [String] Simple instruction for the agent
      # @param user [Object, nil] Optional user for session
      # @param params [Hash] Additional parameters
      # @return [Hash] Execution result
      def execute_task(instructions, user: nil, **params)
        agent = new(params.merge(task_instructions: instructions))
        agent.execute_with_session(user: user)
      end
    end

    # Initialize the browser agent
    def initialize(params = {})
      super(params) if defined?(super)

      @task_instructions = params[:task_instructions] || params[:instructions]
      @session = nil
      @mcp_client = nil
      @execution_log = []

      initialize_browser_session
    end

    # Execute the agent task with session management
    #
    # @param user [Object, nil] Optional user for session
    # @param resume_session_id [Integer, nil] Optional session ID to resume
    # @return [Hash] Execution result
    def execute_with_session(user: nil, resume_session_id: nil)
      setup_session(user: user, resume_session_id: resume_session_id)

      begin
        result = execute_task_loop
        complete_session(result)
        result
      rescue AuthenticationRequiredError => e
        handle_auth_required(e)
      rescue => e
        handle_execution_error(e)
      end
    end

    # Main execution loop
    def execute_task_loop
      return resume_from_checkpoint if session&.resumable?

      # Start fresh execution
      execute_instructions(@task_instructions)
    end

    # Execute given instructions using the LLM
    #
    # @param instructions [String] Instructions to execute
    # @return [Hash] Execution result
    def execute_instructions(instructions)
      log_execution("Starting task: #{instructions}")

      # Build the prompt with browser tools
      messages = build_task_messages(instructions)

      # Execute with tool loop
      loop do
        response = generate_response(messages)

        if response.tool_calls.present?
          tool_results = execute_tool_calls(response.tool_calls)

          # Check if we need to pause for auth
          if should_pause_for_auth?(tool_results)
            return { status: :waiting_for_auth, results: tool_results }
          end

          # Check if we need user input
          if should_pause_for_user?(tool_results)
            return { status: :waiting_for_user, results: tool_results }
          end

          messages << { role: "assistant", content: response.content, tool_calls: response.tool_calls }
          messages << { role: "tool", content: format_tool_results(tool_results) }
        else
          # Task complete
          log_execution("Task completed: #{response.content}")
          return {
            status: :completed,
            result: response.content,
            execution_log: @execution_log
          }
        end
      end
    end

    # Resume from a saved checkpoint
    def resume_from_checkpoint
      checkpoint = session.checkpoint_data
      log_execution("Resuming from checkpoint: #{checkpoint[:label] || 'unknown'}")

      # Restore browser state
      if (browser_state = session.restore_browser_state)
        restore_browser_state(browser_state)
      end

      # Continue with original instructions
      execute_instructions(@task_instructions)
    end

    # Execute Playwright tool calls
    #
    # @param tool_calls [Array<Hash>] Tool calls from LLM
    # @return [Array<Hash>] Tool results
    def execute_tool_calls(tool_calls)
      tool_calls.map do |tool_call|
        name = tool_call[:function][:name] || tool_call[:name]
        args = parse_tool_arguments(tool_call)

        result = execute_playwright_tool(name, args)
        save_tool_fragment(name, args, result)

        {
          tool_call_id: tool_call[:id],
          name: name,
          result: result
        }
      end
    end

    # Execute a single Playwright tool
    #
    # @param name [String] Tool name
    # @param args [Hash] Tool arguments
    # @return [Hash] Tool result
    def execute_playwright_tool(name, args)
      log_execution("Executing tool: #{name}", args: args)

      # Map tool names to Playwright MCP actions
      action = tool_name_to_action(name)

      result = execute_playwright_action(action, **args.symbolize_keys)

      # Check for auth indicators
      check_for_auth_requirement(result)

      result
    rescue => e
      log_execution("Tool error: #{name}", error: e.message)
      { error: e.message, status: :failed }
    end

    # Implement Playwright MCP action execution
    def execute_playwright_action(action, **params)
      # Use MCP client if available, otherwise use tool execution
      if @mcp_client
        @mcp_client.call(action, **params)
      else
        # Fall back to tool execution in the agent context
        perform_tool_action(action, params)
      end
    end

    private

    def setup_session(user:, resume_session_id:)
      if resume_session_id
        @session = Session.find(resume_session_id)
        @session.resume! if @session.resumable?
      else
        prompt = find_or_create_prompt
        @session = prompt.create_session(user: user)
      end

      # Set up context for persistence
      if respond_to?(:load_browser_session)
        load_browser_session(contextable: @session)
      end
    end

    def find_or_create_prompt
      Prompt.latest("browser-assistant") || Prompt.create!(
        name: "browser-assistant",
        version: "1.0.0",
        model: ActivePrompt.configuration.default_model,
        instructions: default_browser_instructions,
        tools: PLAYWRIGHT_TOOLS.map { |t| { name: t } }
      )
    end

    def build_task_messages(instructions)
      system_prompt = <<~PROMPT
        #{default_browser_instructions}

        ## Current Task
        #{instructions}
      PROMPT

      messages = [{ role: "system", content: system_prompt }]

      # Add conversation history from session
      if session&.messages&.any?
        messages.concat(session.conversation_messages)
      end

      # Add initial user message
      messages << { role: "user", content: "Please execute this task: #{instructions}" }

      messages
    end

    def generate_response(messages)
      # Use the agent's prompt method
      if respond_to?(:prompt)
        prompt(messages: messages, tools: playwright_tool_definitions)
      else
        raise NotImplementedError, "Agent must implement prompt method or include ActiveAgent"
      end
    end

    def playwright_tool_definitions
      PLAYWRIGHT_TOOLS.map do |tool_name|
        {
          type: "function",
          function: {
            name: tool_name,
            description: tool_description_for(tool_name),
            parameters: tool_parameters_for(tool_name)
          }
        }
      end
    end

    def tool_name_to_action(name)
      # Convert tool names like browser_navigate to :navigate
      name.to_s.sub(/^browser_/, "").to_sym
    end

    def parse_tool_arguments(tool_call)
      args = tool_call.dig(:function, :arguments) || tool_call[:arguments] || {}
      args.is_a?(String) ? JSON.parse(args, symbolize_names: true) : args.symbolize_keys
    end

    def format_tool_results(results)
      results.map do |r|
        "Tool: #{r[:name]}\nResult: #{r[:result].to_json}"
      end.join("\n\n")
    end

    def save_tool_fragment(name, args, result)
      return unless session

      Fragment.create_tool_output(
        session: session,
        tool_name: name,
        input: args,
        output: result
      )
    end

    def check_for_auth_requirement(result)
      # Check for common auth indicators
      auth_indicators = [
        /login/i,
        /sign.?in/i,
        /authentication/i,
        /password/i,
        /captcha/i,
        /verify/i
      ]

      if result.is_a?(Hash) && result[:snapshot]
        snapshot_text = result[:snapshot].to_s.downcase

        auth_indicators.each do |indicator|
          if snapshot_text.match?(indicator)
            @auth_required = true
            break
          end
        end
      end
    end

    def should_pause_for_auth?(tool_results)
      @auth_required || tool_results.any? { |r| r[:result][:auth_required] }
    end

    def should_pause_for_user?(tool_results)
      tool_results.any? { |r| r[:result][:user_input_needed] }
    end

    def handle_auth_required(error)
      log_execution("Authentication required", auth_type: error.auth_type)

      session.pause!(
        reason: :auth,
        checkpoint: {
          url: @current_url,
          auth_type: error.auth_type,
          instructions: error.instructions
        }
      )

      # Create auth fragment
      Fragment.create_authentication(
        session: session,
        auth_type: error.auth_type,
        target_url: @current_url,
        instructions: error.instructions
      )

      # Call auth callback if configured
      callback = ActivePrompt.configuration.auth_callback
      callback&.call(session, error)

      {
        status: :waiting_for_auth,
        session_id: session.id,
        auth_type: error.auth_type,
        instructions: error.instructions,
        message: "Authentication required. Please log in and then resume the session."
      }
    end

    def handle_execution_error(error)
      log_execution("Execution error", error: error.message, backtrace: error.backtrace&.first(5))

      session&.fail!(error: error)

      {
        status: :failed,
        error: error.message,
        execution_log: @execution_log
      }
    end

    def complete_session(result)
      session&.complete!(result: result)
    end

    def log_execution(message, **data)
      entry = {
        timestamp: Time.current.iso8601,
        message: message,
        **data
      }

      @execution_log << entry
      Rails.logger.info("[BrowserAgent] #{message}") if defined?(Rails)
    end

    def default_browser_instructions
      <<~INSTRUCTIONS
        You are a browser automation assistant. You can navigate web pages, interact with elements,
        fill forms, and extract information.

        ## Available Tools
        You have access to Playwright browser automation tools. Use them to complete tasks.

        ## Key Tools
        - browser_navigate: Go to a URL
        - browser_snapshot: Get the current page structure (use this to understand what's on the page)
        - browser_click: Click an element (use the ref from snapshot)
        - browser_type: Type text into a field
        - browser_fill_form: Fill multiple form fields at once
        - browser_take_screenshot: Capture a screenshot
        - browser_wait_for: Wait for an element or text to appear

        ## Guidelines
        1. Always take a snapshot first to understand the page structure
        2. Use element refs from the snapshot for interactions
        3. Wait for pages to load after navigation
        4. If you encounter a login page or authentication, stop and request user assistance
        5. Be efficient - complete tasks in as few steps as possible

        ## Authentication Handling
        If you encounter a login page, CAPTCHA, or any authentication requirement:
        1. Stop immediately
        2. Report that authentication is required
        3. Wait for the user to complete authentication before proceeding
      INSTRUCTIONS
    end

    def tool_description_for(name)
      descriptions = {
        "browser_navigate" => "Navigate to a URL",
        "browser_snapshot" => "Get accessibility snapshot of the current page",
        "browser_click" => "Click an element on the page",
        "browser_type" => "Type text into an element",
        "browser_fill_form" => "Fill multiple form fields",
        "browser_take_screenshot" => "Take a screenshot of the page",
        "browser_press_key" => "Press a keyboard key",
        "browser_evaluate" => "Evaluate JavaScript on the page",
        "browser_wait_for" => "Wait for text, element, or time",
        "browser_console_messages" => "Get browser console messages",
        "browser_network_requests" => "Get network requests",
        "browser_tabs" => "Manage browser tabs",
        "browser_hover" => "Hover over an element",
        "browser_select_option" => "Select option in a dropdown",
        "browser_drag" => "Drag and drop elements",
        "browser_handle_dialog" => "Handle browser dialogs",
        "browser_file_upload" => "Upload files",
        "browser_close" => "Close the browser",
        "browser_navigate_back" => "Go back in browser history",
        "browser_resize" => "Resize browser window",
        "browser_install" => "Install the browser"
      }
      descriptions[name] || "Browser automation tool"
    end

    def tool_parameters_for(name)
      # Return JSON schema for each tool's parameters
      schemas = {
        "browser_navigate" => {
          type: "object",
          properties: {
            url: { type: "string", description: "URL to navigate to" }
          },
          required: ["url"]
        },
        "browser_click" => {
          type: "object",
          properties: {
            ref: { type: "string", description: "Element reference from snapshot" },
            element: { type: "string", description: "Human-readable element description" }
          },
          required: ["ref"]
        },
        "browser_type" => {
          type: "object",
          properties: {
            ref: { type: "string", description: "Element reference" },
            text: { type: "string", description: "Text to type" },
            submit: { type: "boolean", description: "Press Enter after typing" }
          },
          required: ["ref", "text"]
        },
        "browser_snapshot" => {
          type: "object",
          properties: {}
        },
        "browser_take_screenshot" => {
          type: "object",
          properties: {
            filename: { type: "string", description: "Output filename" },
            full_page: { type: "boolean", description: "Capture full page" }
          }
        },
        "browser_wait_for" => {
          type: "object",
          properties: {
            text: { type: "string", description: "Text to wait for" },
            time: { type: "number", description: "Time to wait in seconds" }
          }
        }
      }

      schemas[name] || { type: "object", properties: {} }
    end

    def truncate_url(url, length = 50)
      return url if url.length <= length

      "#{url[0..length]}..."
    end

    def perform_tool_action(action, params)
      # This is a fallback for when MCP client is not available
      # In practice, this would be overridden or use actual Playwright bindings
      { action: action, params: params, status: :executed }
    end
  end
end

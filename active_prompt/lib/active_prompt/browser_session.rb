# frozen_string_literal: true

module ActivePrompt
  # BrowserSession provides integration with Playwright for browser automation.
  #
  # This module enables agents to control browsers through the Playwright MCP
  # (Model Context Protocol), with support for session persistence, authentication
  # workflows, and state restoration.
  #
  # @example Using BrowserSession in an agent
  #   class BrowserAgent < ApplicationAgent
  #     include ActivePrompt::BrowserSession
  #
  #     def navigate_and_extract
  #       with_browser_session do
  #         navigate_to("https://example.com")
  #         wait_for_selector("h1")
  #         extract_content("h1")
  #       end
  #     end
  #   end
  #
  module BrowserSession
    extend ActiveSupport::Concern

    # Browser states
    STATES = %i[
      idle
      navigating
      waiting_for_auth
      waiting_for_user
      extracting
      error
    ].freeze

    included do
      attr_accessor :browser_state, :current_url, :page_title
      attr_accessor :auth_required, :auth_instructions

      # Callbacks for browser events
      class_attribute :_browser_callbacks, default: {}
    end

    class_methods do
      # Register callback for browser events
      #
      # @param event [Symbol] Event name (:auth_required, :navigation_complete, :error)
      # @param method_name [Symbol] Method to call
      def on_browser_event(event, method_name = nil, &block)
        self._browser_callbacks = _browser_callbacks.merge(event => method_name || block)
      end
    end

    # Initialize browser session state
    def initialize_browser_session
      @browser_state = :idle
      @current_url = nil
      @page_title = nil
      @auth_required = false
      @auth_instructions = nil
      @browser_history = []
    end

    # Execute block with browser session management
    #
    # @yield Block to execute with browser context
    # @return [Object] Result of the block
    def with_browser_session
      initialize_browser_session

      begin
        result = yield
        complete_browser_session(result)
        result
      rescue AuthenticationRequiredError => e
        pause_for_authentication(e)
        raise
      rescue => e
        handle_browser_error(e)
        raise
      end
    end

    # Navigate to a URL
    #
    # @param url [String] URL to navigate to
    # @param wait_until [Symbol] Wait condition (:load, :domcontentloaded, :networkidle)
    # @return [Hash] Navigation result
    def navigate_to(url, wait_until: :load)
      @browser_state = :navigating
      @current_url = url

      result = execute_playwright_action(:navigate, url: url, wait_until: wait_until)

      @browser_history << {
        url: url,
        timestamp: Time.current,
        title: result[:title]
      }

      @page_title = result[:title]
      @browser_state = :idle

      trigger_browser_callback(:navigation_complete, url: url, title: @page_title)
      cache_browser_state

      result
    end

    # Click an element
    #
    # @param selector [String] Element selector or ref
    # @param options [Hash] Click options
    # @return [Hash] Click result
    def click_element(selector, **options)
      execute_playwright_action(:click, ref: selector, **options)
    end

    # Type text into an element
    #
    # @param selector [String] Element selector or ref
    # @param text [String] Text to type
    # @param options [Hash] Type options
    # @return [Hash] Type result
    def type_text(selector, text, **options)
      execute_playwright_action(:type, ref: selector, text: text, **options)
    end

    # Fill a form
    #
    # @param fields [Array<Hash>] Field definitions
    # @return [Hash] Fill result
    def fill_form(fields)
      execute_playwright_action(:fill_form, fields: fields)
    end

    # Take a screenshot
    #
    # @param filename [String, nil] Optional filename
    # @param full_page [Boolean] Capture full page
    # @return [Hash] Screenshot result
    def take_screenshot(filename: nil, full_page: false)
      execute_playwright_action(:screenshot, filename: filename, full_page: full_page)
    end

    # Get page snapshot (accessibility tree)
    #
    # @return [Hash] Page snapshot
    def get_page_snapshot
      execute_playwright_action(:snapshot)
    end

    # Wait for a selector to appear
    #
    # @param selector [String] Element selector
    # @param timeout [Integer] Timeout in milliseconds
    # @return [Hash] Wait result
    def wait_for_selector(selector, timeout: 30_000)
      execute_playwright_action(:wait_for, selector: selector, timeout: timeout)
    end

    # Wait for navigation to complete
    #
    # @param timeout [Integer] Timeout in milliseconds
    # @return [Hash] Wait result
    def wait_for_navigation(timeout: 30_000)
      execute_playwright_action(:wait_for_navigation, timeout: timeout)
    end

    # Extract text content from the page
    #
    # @param selector [String, nil] Optional selector to extract from
    # @return [String] Extracted text
    def extract_content(selector = nil)
      result = execute_playwright_action(:evaluate,
        function: selector ?
          "() => document.querySelector('#{selector}')?.textContent" :
          "() => document.body.innerText"
      )
      result[:result]
    end

    # Check if authentication is needed
    #
    # @return [Boolean]
    def authentication_required?
      @auth_required
    end

    # Pause session for user authentication
    #
    # @param auth_type [Symbol] Type of auth needed
    # @param instructions [String, nil] Instructions for user
    # @return [Hash] Pause state
    def request_authentication(auth_type:, instructions: nil)
      @auth_required = true
      @auth_instructions = instructions
      @browser_state = :waiting_for_auth

      trigger_browser_callback(:auth_required,
        auth_type: auth_type,
        url: @current_url,
        instructions: instructions
      )

      # Save state for resumption
      save_state_for_resumption(
        reason: :authentication,
        auth_type: auth_type,
        instructions: instructions
      )

      { status: :waiting_for_auth, auth_type: auth_type, url: @current_url }
    end

    # Resume after authentication
    #
    # @return [Boolean]
    def resume_after_authentication
      @auth_required = false
      @auth_instructions = nil
      @browser_state = :idle

      true
    end

    # Pause for user interaction
    #
    # @param prompt [String] What to ask the user
    # @param options [Hash] Options for the pause
    # @return [Hash] Pause state
    def wait_for_user_interaction(prompt:, **options)
      @browser_state = :waiting_for_user

      trigger_browser_callback(:user_interaction_needed,
        prompt: prompt,
        url: @current_url,
        **options
      )

      save_state_for_resumption(
        reason: :user_interaction,
        prompt: prompt,
        **options
      )

      { status: :waiting_for_user, prompt: prompt }
    end

    # Save current browser state for session resumption
    #
    # @return [Hash] Saved state
    def save_state_for_resumption(reason: :checkpoint, **data)
      state = {
        url: @current_url,
        title: @page_title,
        browser_state: @browser_state,
        history: @browser_history,
        reason: reason,
        saved_at: Time.current.iso8601,
        **data
      }

      # Get cookies and storage if available
      begin
        cookies_result = execute_playwright_action(:evaluate,
          function: "() => document.cookie"
        )
        state[:cookies] = cookies_result[:result]
      rescue
        # Cookies might not be accessible
      end

      cache_browser_state(state)
      state
    end

    # Restore browser state from saved data
    #
    # @param state [Hash] Saved state to restore
    # @return [Boolean]
    def restore_browser_state(state)
      return false unless state

      @current_url = state[:url]
      @page_title = state[:title]
      @browser_history = state[:history] || []

      # Navigate to saved URL
      if @current_url
        navigate_to(@current_url, wait_until: :networkidle)
      end

      true
    end

    # Get console messages from the browser
    #
    # @param level [Symbol] Log level (:error, :warning, :info, :debug)
    # @return [Array<Hash>] Console messages
    def get_console_messages(level: :info)
      result = execute_playwright_action(:console_messages, level: level)
      result[:messages] || []
    end

    # Get network requests
    #
    # @param include_static [Boolean] Include static resources
    # @return [Array<Hash>] Network requests
    def get_network_requests(include_static: false)
      result = execute_playwright_action(:network_requests, include_static: include_static)
      result[:requests] || []
    end

    private

    def execute_playwright_action(action, **params)
      # This will be implemented by the BrowserAgent to call Playwright MCP
      raise NotImplementedError, "Subclass must implement execute_playwright_action"
    end

    def cache_browser_state(state = nil)
      state ||= {
        url: @current_url,
        title: @page_title,
        browser_state: @browser_state,
        history: @browser_history,
        cached_at: Time.current.iso8601
      }

      if respond_to?(:context) && context.respond_to?(:session)
        context.session.save_browser_state!(state)
      end

      state
    end

    def trigger_browser_callback(event, **data)
      callback = _browser_callbacks[event]
      return unless callback

      if callback.is_a?(Symbol)
        send(callback, **data)
      elsif callback.respond_to?(:call)
        callback.call(self, **data)
      end
    end

    def complete_browser_session(result)
      cache_browser_state
      @browser_state = :idle
    end

    def pause_for_authentication(error)
      @browser_state = :waiting_for_auth
      @auth_required = true
      @auth_instructions = error.message

      save_state_for_resumption(
        reason: :authentication,
        error: error.message
      )
    end

    def handle_browser_error(error)
      @browser_state = :error

      save_state_for_resumption(
        reason: :error,
        error_class: error.class.name,
        error_message: error.message
      )

      trigger_browser_callback(:error,
        error: error,
        url: @current_url
      )
    end
  end

  # Error raised when authentication is required
  class AuthenticationRequiredError < Error
    attr_reader :auth_type, :url, :instructions

    def initialize(message = nil, auth_type: :login, url: nil, instructions: nil)
      @auth_type = auth_type
      @url = url
      @instructions = instructions
      super(message || "Authentication required: #{auth_type}")
    end
  end
end

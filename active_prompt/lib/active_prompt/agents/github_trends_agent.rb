# frozen_string_literal: true

module ActivePrompt
  module Agents
    # GitHubTrendsAgent discovers trending repositories on GitHub.
    #
    # This agent navigates to GitHub's trending page, applies optional filters
    # for language and timeframe, and extracts repository information.
    #
    # @example Basic usage
    #   agent = GitHubTrendsAgent.new
    #   result = agent.fetch_trends(language: "ruby", count: 5)
    #
    # @example With session persistence
    #   agent = GitHubTrendsAgent.new
    #   result = agent.fetch_trends_with_session(
    #     language: "python",
    #     timeframe: "weekly",
    #     user: current_user
    #   )
    #
    class GitHubTrendsAgent
      include BrowserAgent

      TRENDING_URL = "https://github.com/trending"

      LANGUAGE_MAP = {
        "ruby" => "Ruby",
        "python" => "Python",
        "javascript" => "JavaScript",
        "typescript" => "TypeScript",
        "go" => "Go",
        "rust" => "Rust",
        "java" => "Java",
        "c++" => "C++",
        "c#" => "C#",
        "php" => "PHP",
        "swift" => "Swift",
        "kotlin" => "Kotlin"
      }.freeze

      TIMEFRAMES = %w[daily weekly monthly].freeze

      attr_reader :language, :timeframe, :count

      def initialize(params = {})
        super(params)

        @language = params[:language]
        @timeframe = params[:timeframe] || "daily"
        @count = params[:count] || 5

        @task_instructions = build_instructions
      end

      # Fetch trending repositories
      #
      # @param language [String, nil] Programming language filter
      # @param timeframe [String] Time range (daily, weekly, monthly)
      # @param count [Integer] Number of repositories to return
      # @return [Hash] Result with repositories array
      def fetch_trends(language: nil, timeframe: "daily", count: 5)
        @language = language
        @timeframe = timeframe
        @count = count
        @task_instructions = build_instructions

        with_browser_session do
          navigate_to_trending
          apply_filters
          extract_repositories
        end
      end

      # Fetch trends with session persistence for resumption
      #
      # @param user [Object, nil] User for session association
      # @param kwargs [Hash] Same options as fetch_trends
      # @return [Hash] Result with session_id for resumption
      def fetch_trends_with_session(user: nil, **kwargs)
        @language = kwargs[:language]
        @timeframe = kwargs[:timeframe] || "daily"
        @count = kwargs[:count] || 5
        @task_instructions = build_instructions

        execute_with_session(user: user)
      end

      # Execute the main task loop
      def execute_task_loop
        navigate_to_trending
        apply_filters
        extract_repositories
      end

      private

      def build_instructions
        parts = ["Find the top #{@count} trending repositories on GitHub"]

        if @language
          parts << "filtered by #{@language}"
        end

        parts << "for the #{@timeframe} timeframe"
        parts.join(" ")
      end

      def navigate_to_trending
        log_execution("Navigating to GitHub trending page")

        url = build_trending_url
        navigate_to(url, wait_until: :networkidle)

        # Wait for content to load
        wait_for_selector("article.Box-row", timeout: 10_000)

        save_fragment(:navigation, url: url)
      end

      def build_trending_url
        url = TRENDING_URL

        params = []
        params << "since=#{@timeframe}" if @timeframe && @timeframe != "daily"

        if @language
          lang = LANGUAGE_MAP[@language.downcase] || @language
          url = "#{url}/#{lang.downcase}"
        end

        params.any? ? "#{url}?#{params.join('&')}" : url
      end

      def apply_filters
        # Filters are applied via URL, but we can also interact with UI
        # if more complex filtering is needed

        if @timeframe && @timeframe != "daily"
          log_execution("Applying timeframe filter: #{@timeframe}")

          # Click the timeframe dropdown and select option
          snapshot = get_page_snapshot

          # Find and click the date range selector
          begin
            click_element('[data-ga-click*="date range"]')
            wait_for_selector("a[href*='since=#{@timeframe}']", timeout: 5_000)
            click_element("a[href*='since=#{@timeframe}']")
            wait_for_navigation
          rescue StandardError => e
            log_execution("Filter interaction failed, using URL params", error: e.message)
          end
        end

        save_fragment(:filter_applied, language: @language, timeframe: @timeframe)
      end

      def extract_repositories
        log_execution("Extracting repository data")

        # Use JavaScript to extract repository data
        result = execute_playwright_action(:evaluate, function: extraction_script)

        repositories = result[:result] || []
        repositories = repositories.take(@count)

        # Enhance with additional data if needed
        repositories = enhance_repository_data(repositories)

        save_fragment(:extracted_data, count: repositories.length)

        {
          status: :completed,
          repositories: repositories,
          metadata: {
            language_filter: @language,
            timeframe: @timeframe,
            fetched_at: Time.current.iso8601,
            total_found: repositories.length
          }
        }
      end

      def extraction_script
        <<~JS
          () => {
            const repos = [];
            const articles = document.querySelectorAll('article.Box-row');

            articles.forEach((article, index) => {
              const nameEl = article.querySelector('h2 a');
              const descEl = article.querySelector('p');
              const starsEl = article.querySelector('a[href$="/stargazers"]');
              const langEl = article.querySelector('[itemprop="programmingLanguage"]');
              const todayEl = article.querySelector('.float-sm-right, .d-inline-block.float-sm-right');

              if (nameEl) {
                const fullName = nameEl.textContent.trim().replace(/\\s+/g, '');

                repos.push({
                  rank: index + 1,
                  name: fullName,
                  url: 'https://github.com' + nameEl.getAttribute('href'),
                  description: descEl ? descEl.textContent.trim() : '',
                  stars: starsEl ? parseInt(starsEl.textContent.trim().replace(/,/g, '')) : 0,
                  language: langEl ? langEl.textContent.trim() : 'Unknown',
                  stars_today: todayEl ? (parseInt(todayEl.textContent.match(/(\\d+)/)?.[1]) || 0) : 0
                });
              }
            });

            return repos;
          }
        JS
      end

      def enhance_repository_data(repositories)
        repositories.map do |repo|
          repo.merge(
            extracted_at: Time.current.iso8601,
            filter_language: @language,
            filter_timeframe: @timeframe
          )
        end
      end

      def save_fragment(type, **data)
        return unless session

        Fragment.create_checkpoint(
          session: session,
          label: "github_trends_#{type}",
          data: data.merge(step: type, timestamp: Time.current.iso8601)
        )
      end

      # Override to handle GitHub-specific auth scenarios
      def check_for_auth_requirement(result)
        super

        # Check for rate limiting
        if result.is_a?(Hash) && result[:snapshot]
          snapshot_text = result[:snapshot].to_s.downcase

          if snapshot_text.include?("rate limit") || snapshot_text.include?("too many requests")
            @auth_required = true
            @auth_instructions = "GitHub rate limit reached. Please wait or log in to continue."
          end
        end
      end

      # Generate default tool definitions
      def default_tools
        [
          {
            type: "function",
            function: {
              name: "extract_trending_repos",
              description: "Extract trending repository data from the current GitHub page",
              parameters: {
                type: "object",
                properties: {
                  count: {
                    type: "integer",
                    description: "Number of repositories to extract",
                    default: 5
                  }
                }
              }
            }
          }
        ] + super
      end
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "fileutils"

module SolidAgent
  module AgentManifest
    module Registry
      # Client provides HTTP API access to the ActiveAgents registry.
      #
      # @example Search for agents
      #   client = Registry::Client.new
      #   results = client.search(q: "research", tags: ["assistant"])
      #
      # @example Download an agent
      #   client.download("@anthropic/research-assistant", path: "./agents/")
      #
      # @example Publish an agent
      #   client = Registry::Client.new(token: "aa_live_xxx")
      #   client.publish("./research-assistant.agent.md")
      #
      class Client
        BASE_URL = "https://api.activeagents.ai/v1"

        attr_reader :base_url, :token

        # Initialize a new client
        #
        # @param token [String, nil] Auth token (uses Auth.token if nil)
        # @param base_url [String] API base URL
        def initialize(token: nil, base_url: BASE_URL)
          @token = token || Auth.token
          @base_url = base_url
        end

        # === Discovery Methods ===

        # Search for agents
        #
        # @param q [String, nil] Search query
        # @param tags [Array<String>, nil] Filter by tags
        # @param framework [String, nil] Filter by framework (e.g., "activeagent", "crewai")
        # @param author [String, nil] Filter by author
        # @param sort [String] Sort order ("popular", "recent", "name")
        # @param page [Integer] Page number
        # @param per_page [Integer] Results per page
        # @return [Hash] Search results with :agents, :total, :page keys
        def search(q: nil, tags: nil, framework: nil, author: nil, sort: "popular", page: 1, per_page: 20)
          params = {
            q: q,
            tags: tags&.join(","),
            framework: framework,
            author: author,
            sort: sort,
            page: page,
            per_page: per_page
          }.compact

          get("/agents", params)
        end

        # Get an agent by name
        #
        # @param name [String] Agent name (e.g., "@anthropic/research-assistant")
        # @param version [String, nil] Specific version (latest if nil)
        # @return [Hash] Agent metadata
        def get(name, version: nil)
          path = version ? "/agents/#{encode_name(name)}/versions/#{version}" : "/agents/#{encode_name(name)}"
          get_request(path)
        end

        # List all versions of an agent
        #
        # @param name [String] Agent name
        # @return [Array<Hash>] Version list
        def versions(name)
          get_request("/agents/#{encode_name(name)}/versions")
        end

        # === Download Methods ===

        # Download an agent manifest
        #
        # @param name [String] Agent name
        # @param version [String, nil] Specific version
        # @param path [String, nil] Download directory (current dir if nil)
        # @param format [Symbol] Output format (:agent_md, :dotprompt, etc.)
        # @return [String] Path to downloaded file
        def download(name, version: nil, path: nil, format: :agent_md)
          # Get agent metadata
          agent = get(name, version: version)

          # Determine output path
          output_dir = path || Dir.pwd
          FileUtils.mkdir_p(output_dir)

          filename = agent_filename(agent, format)
          output_path = File.join(output_dir, filename)

          # Download content
          content_url = agent["download_url"] || agent.dig("links", "download")
          if content_url
            content = fetch_content(content_url)
          else
            # Fetch from content endpoint
            content = get_request("/agents/#{encode_name(name)}/content", accept: "text/markdown")
          end

          # Convert format if needed
          source_format = agent["format"]&.to_sym || :agent_md
          if format != source_format
            manifest = ParserRegistry.parse_string(content, format: source_format)
            content = ExporterRegistry.export(manifest, format)
          end

          File.write(output_path, content, encoding: "UTF-8")
          output_path
        end

        # Download a specific file from an agent package
        #
        # @param name [String] Agent name
        # @param file_path [String] Path within the package
        # @param version [String, nil] Specific version
        # @return [String] File content
        def download_file(name, file_path, version: nil)
          path = "/agents/#{encode_name(name)}/files/#{file_path}"
          path += "?version=#{version}" if version
          get_request(path, accept: "*/*")
        end

        # === Publishing Methods ===

        # Publish an agent manifest
        #
        # @param path [String] Path to manifest file
        # @param tag [String] Version tag ("latest", "beta", etc.)
        # @param scope [String, nil] Organization scope
        # @param access [String] Access level ("public", "private")
        # @return [Hash] Published agent info
        def publish(path, tag: "latest", scope: nil, access: "public")
          require_auth!

          manifest = AgentManifest.parse(path)
          AgentManifest.validate!(manifest, strict: true)

          content = File.read(path, encoding: "UTF-8")
          format = ParserRegistry.detect_format(path)

          body = {
            name: scope ? "#{scope}/#{manifest.name}" : manifest.name,
            version: manifest.version,
            tag: tag,
            access: access,
            format: format,
            content: content,
            metadata: {
              description: manifest.description,
              tags: manifest.tags,
              model: manifest.model,
              author: manifest.author,
              license: manifest.license,
              repository: manifest.repository
            }
          }

          post("/agents", body)
        end

        # Deprecate a version
        #
        # @param name [String] Agent name
        # @param version [String] Version to deprecate
        # @param message [String] Deprecation message
        # @return [Hash] Updated version info
        def deprecate(name, version, message:)
          require_auth!
          patch("/agents/#{encode_name(name)}/versions/#{version}", { deprecated: true, deprecation_message: message })
        end

        # Unpublish a version
        #
        # @param name [String] Agent name
        # @param version [String] Version to remove
        # @return [Boolean]
        def unpublish(name, version)
          require_auth!
          delete("/agents/#{encode_name(name)}/versions/#{version}")
          true
        end

        # === User Actions ===

        # Star an agent
        #
        # @param name [String] Agent name
        # @return [Boolean]
        def star(name)
          require_auth!
          post("/agents/#{encode_name(name)}/star", {})
          true
        end

        # Unstar an agent
        #
        # @param name [String] Agent name
        # @return [Boolean]
        def unstar(name)
          require_auth!
          delete("/agents/#{encode_name(name)}/star")
          true
        end

        # Fork an agent
        #
        # @param name [String] Source agent name
        # @param new_name [String] Name for the fork
        # @param scope [String, nil] Organization scope
        # @return [Hash] Forked agent info
        def fork(name, new_name:, scope: nil)
          require_auth!
          post("/agents/#{encode_name(name)}/fork", { new_name: new_name, scope: scope })
        end

        # === Sandbox Methods ===

        # Run an agent in the sandbox
        #
        # @param name [String] Agent name
        # @param input [Hash] Input parameters
        # @param model [String, nil] Override model
        # @param stream [Boolean] Enable streaming
        # @return [Hash] Run result or job info
        def run(name, input:, model: nil, stream: false)
          require_auth!
          body = { input: input, model: model, stream: stream }.compact
          post("/agents/#{encode_name(name)}/run", body)
        end

        # Get status of a sandbox run
        #
        # @param run_id [String] Run ID
        # @return [Hash] Run status
        def run_status(run_id)
          require_auth!
          get_request("/runs/#{run_id}")
        end

        # === Account Methods ===

        # Get current user info
        #
        # @return [Hash] User info
        def me
          require_auth!
          get_request("/me")
        end

        # Get user's starred agents
        #
        # @return [Array<Hash>] Starred agents
        def my_stars
          require_auth!
          get_request("/me/stars")
        end

        # Get user's published agents
        #
        # @return [Array<Hash>] Published agents
        def my_agents
          require_auth!
          get_request("/me/agents")
        end

        private

        def require_auth!
          raise RegistryError, "Authentication required" unless token
        end

        def encode_name(name)
          # Handle scoped names: @scope/name -> @scope%2Fname
          URI.encode_www_form_component(name)
        end

        def agent_filename(agent, format)
          name = agent["name"].to_s.split("/").last
          extension = case format
          when :agent_md then ".agent.md"
          when :dotprompt then ".prompt"
          when :crewai then ".yaml"
          when :github_prompt then ".prompt.md"
          else ".agent.md"
          end
          "#{name}#{extension}"
        end

        def get_request(path, params = {}, accept: "application/json")
          uri = build_uri(path, params.except(:accept))
          request = Net::HTTP::Get.new(uri)
          request["Accept"] = accept
          execute(request)
        end

        def post(path, body)
          uri = build_uri(path)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = body.to_json
          execute(request)
        end

        def patch(path, body)
          uri = build_uri(path)
          request = Net::HTTP::Patch.new(uri)
          request["Content-Type"] = "application/json"
          request.body = body.to_json
          execute(request)
        end

        def delete(path)
          uri = build_uri(path)
          request = Net::HTTP::Delete.new(uri)
          execute(request)
        end

        def build_uri(path, params = {})
          uri = URI.parse("#{base_url}#{path}")
          uri.query = URI.encode_www_form(params) if params.any?
          uri
        end

        def execute(request)
          # Add auth header if available
          if token
            request["Authorization"] = "Bearer #{token}"
          end

          request["User-Agent"] = "SolidAgent/#{SolidAgent::VERSION}"

          uri = request.uri
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = 30

          response = http.request(request)

          case response
          when Net::HTTPSuccess
            parse_response(response)
          when Net::HTTPUnauthorized
            raise RegistryError, "Authentication failed. Please login again."
          when Net::HTTPForbidden
            raise RegistryError, "Access denied"
          when Net::HTTPNotFound
            raise RegistryError, "Resource not found"
          when Net::HTTPUnprocessableEntity
            error_body = parse_response(response) rescue {}
            message = error_body["error"] || error_body["message"] || "Validation failed"
            raise ValidationError, message
          else
            error_body = parse_response(response) rescue {}
            message = error_body["error"] || error_body["message"] || "Request failed: #{response.code}"
            raise RegistryError, message
          end
        end

        def parse_response(response)
          return response.body unless response["Content-Type"]&.include?("application/json")

          JSON.parse(response.body)
        end

        def fetch_content(url)
          uri = URI.parse(url)
          Net::HTTP.get(uri)
        end
      end
    end
  end
end

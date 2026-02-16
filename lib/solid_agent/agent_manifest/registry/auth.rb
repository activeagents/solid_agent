# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    module Registry
      # Auth handles token management for the ActiveAgents registry.
      #
      # Tokens are stored in ~/.activeagent/token by default.
      # Can also be configured via environment variable.
      #
      # @example Check if logged in
      #   Registry::Auth.logged_in?
      #
      # @example Get current token
      #   token = Registry::Auth.token
      #
      # @example Save a token
      #   Registry::Auth.save_token("aa_live_xxx")
      #
      class Auth
        TOKEN_PATH = File.expand_path("~/.activeagent/token")
        TOKEN_ENV_VAR = "ACTIVEAGENT_TOKEN"

        class << self
          # Get the current authentication token
          #
          # Checks in order:
          # 1. Environment variable (ACTIVEAGENT_TOKEN)
          # 2. Token file (~/.activeagent/token)
          #
          # @return [String, nil] The token or nil if not authenticated
          def token
            # Check environment variable first
            env_token = ENV[TOKEN_ENV_VAR]
            return env_token if env_token.present?

            # Check token file
            return nil unless File.exist?(TOKEN_PATH)

            File.read(TOKEN_PATH).strip.presence
          end

          # Save a token to the token file
          #
          # @param new_token [String] The token to save
          # @return [Boolean] true if saved successfully
          def save_token(new_token)
            # Ensure directory exists
            FileUtils.mkdir_p(File.dirname(TOKEN_PATH))

            # Write token with secure permissions
            File.write(TOKEN_PATH, new_token.strip)
            File.chmod(0o600, TOKEN_PATH)

            true
          rescue StandardError => e
            raise RegistryError, "Failed to save token: #{e.message}"
          end

          # Clear the saved token
          #
          # @return [Boolean] true if cleared successfully
          def clear_token
            return true unless File.exist?(TOKEN_PATH)

            File.delete(TOKEN_PATH)
            true
          rescue StandardError => e
            raise RegistryError, "Failed to clear token: #{e.message}"
          end

          # Check if user is logged in
          #
          # @return [Boolean]
          def logged_in?
            token.present?
          end

          # Require authentication, raising if not logged in
          #
          # @raise [RegistryError] if not authenticated
          # @return [String] The token
          def require_token!
            t = token
            raise RegistryError, "Not authenticated. Run 'activeagent login' or set #{TOKEN_ENV_VAR}" unless t

            t
          end

          # Get authorization header for API requests
          #
          # @return [Hash] Authorization header
          def auth_header
            t = token
            return {} unless t

            { "Authorization" => "Bearer #{t}" }
          end
        end
      end
    end
  end
end

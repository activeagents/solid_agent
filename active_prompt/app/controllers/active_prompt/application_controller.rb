# frozen_string_literal: true

module ActivePrompt
  class ApplicationController < ::ApplicationController
    protect_from_forgery with: :exception

    private

    def current_user
      # Override this in your application
      super if defined?(super)
    end
  end
end

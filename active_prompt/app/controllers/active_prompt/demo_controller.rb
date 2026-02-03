# frozen_string_literal: true

module ActivePrompt
  class DemoController < ApplicationController
    # GET /active_prompt/demo
    def show
      render "active_prompt/browser/demo", layout: false
    end
  end
end

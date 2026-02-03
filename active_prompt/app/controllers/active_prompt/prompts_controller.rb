# frozen_string_literal: true

module ActivePrompt
  class PromptsController < ApplicationController
    before_action :set_prompt, only: [:show, :update, :destroy, :duplicate, :versions]

    # GET /active_prompt/prompts
    def index
      @prompts = Prompt.all.order(name: :asc, created_at: :desc)
      @prompts = @prompts.active if params[:active_only]
      @prompts = @prompts.by_name(params[:name]) if params[:name]

      render json: @prompts.map { |p| prompt_json(p) }
    end

    # GET /active_prompt/prompts/latest
    def latest
      name = params.require(:name)
      @prompt = Prompt.latest(name)

      if @prompt
        render json: prompt_json(@prompt, detailed: true)
      else
        render json: { error: "Prompt not found" }, status: :not_found
      end
    end

    # GET /active_prompt/prompts/:id
    def show
      render json: prompt_json(@prompt, detailed: true)
    end

    # POST /active_prompt/prompts
    def create
      @prompt = Prompt.new(prompt_params)

      if @prompt.save
        render json: prompt_json(@prompt, detailed: true), status: :created
      else
        render json: { errors: @prompt.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /active_prompt/prompts/:id
    def update
      if @prompt.update(prompt_params)
        render json: prompt_json(@prompt, detailed: true)
      else
        render json: { errors: @prompt.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /active_prompt/prompts/:id
    def destroy
      @prompt.destroy
      head :no_content
    end

    # POST /active_prompt/prompts/:id/duplicate
    def duplicate
      bump = params[:bump]&.to_sym || :patch
      new_prompt = @prompt.duplicate(bump: bump)

      render json: prompt_json(new_prompt, detailed: true), status: :created
    end

    # GET /active_prompt/prompts/:id/versions
    def versions
      versions = @prompt.all_versions

      render json: versions.map { |p| prompt_json(p) }
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:id])
    end

    def prompt_params
      params.require(:prompt).permit(
        :name,
        :version,
        :model,
        :description,
        :instructions,
        :active,
        tools: [:name, :description, :ref, input_schema: {}],
        config: {},
        extensions: {}
      )
    end

    def prompt_json(prompt, detailed: false)
      json = {
        id: prompt.id,
        name: prompt.name,
        version: prompt.version,
        model: prompt.model,
        description: prompt.description,
        active: prompt.active,
        latest: prompt.latest?,
        created_at: prompt.created_at
      }

      if detailed
        json.merge!(
          instructions: prompt.instructions,
          tools: prompt.tools,
          config: prompt.config,
          extensions: prompt.extensions,
          session_count: prompt.sessions.count
        )
      end

      json
    end
  end
end

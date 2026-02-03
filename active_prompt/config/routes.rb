# frozen_string_literal: true

ActivePrompt::Engine.routes.draw do
  # Prompts (agent configurations)
  resources :prompts do
    member do
      post :duplicate
      get :versions
    end
    collection do
      get :latest
    end
  end

  # Sessions (active agent interactions)
  resources :sessions do
    member do
      post :pause
      post :resume
      post :complete
      get :fragments
      get :messages
      post :add_message
    end
    collection do
      get :active
      get :resumable
      delete :cleanup_expired
    end
  end

  # Fragments (context pieces)
  resources :fragments, only: [:index, :show, :create] do
    collection do
      get :by_type
    end
  end

  # Browser agent execution
  namespace :browser do
    post :execute, to: "agent#execute"
    post :resume, to: "agent#resume"
    get :status, to: "agent#status"
    post :auth_complete, to: "agent#auth_complete"
  end

  # Health check
  get :health, to: "health#show"

  # Demo interface
  get :demo, to: "demo#show"
end

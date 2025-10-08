Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check

  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?


  post "/upload", to: "uploads#create"
  post '/ingest', to: 'ingestions#create'
  post "/evaluate", to: "evaluations#create"
  get "/result/:id", to: "evaluations#show"
  post "/analyze", to: "analyzes#create"
  post "/final_analyze", to: "final_analyses#create"
  # config/routes.rb
  post "/evaluate", to: "evaluations#create"
  get "/result/:id", to: "evaluations#show"

  resources :evaluations, only: [:create, :show]



end

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :api do
    namespace :v1 do
      post   "login",  to: "sessions#create"
      delete "logout", to: "sessions#destroy"

      get "users/me", to: "users#me"
      resources :users, only: [ :index ]

      resources :clusters, only: [ :index, :show ] do
        resources :trees, only: [ :index ]
        resources :actuators, only: [ :index ]
      end

      resources :trees, only: [ :show ] do
        get :telemetry, to: "telemetry#tree_history", on: :member
      end

      resources :gateways, only: [] do
        get :telemetry, to: "telemetry#gateway_history", on: :member
      end

      resources :organizations, only: [ :index, :show ]

      resources :alerts, only: [ :index, :show ] do
        patch :resolve, on: :member
      end

      resources :actuators, only: [] do
        post :execute, on: :member
      end
      get "actuator_commands/:id", to: "actuators#command_status"

      resources :contracts, only: [ :index, :show ] do
        get :stats, on: :collection
      end

      resources :firmwares, only: [ :index, :create ] do
        get  :inventory, on: :collection
        post :deploy, on: :member
      end

      resources :maintenance_records, only: [ :index, :create, :show ]

      resources :oracle_visions, only: [ :index ] do
        post :simulate,      on: :collection
        get  :stream_config,  on: :collection
      end

      post "provisioning/register", to: "provisioning#register"
    end
  end
end

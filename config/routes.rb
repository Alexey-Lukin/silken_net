# frozen_string_literal: true

Rails.application.routes.draw do
  # Reveal health status on /up
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔐 КОНТУР ДОСТУПУ (Authentication)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get    "login",  to: "sessions#new",     as: :login
      post   "login",  to: "sessions#create"
      delete "logout", to: "sessions#destroy", as: :logout

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🏰 ЦЕНТРАЛЬНИЙ ВІВТАР (Dashboard)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :dashboard, only: [ :index ]
      root to: "dashboard#index"

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 👤 ЕКІПАЖ (Users & Identity)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get "users/me", to: "users#me"
      resources :users, only: [ :index, :show ]
      resources :organizations, only: [ :index, :show ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🌳 ВІЙСЬКО ТА СЕКТОРИ (Clusters & Trees)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :clusters, only: [ :index, :show ] do
        resources :trees,     only: [ :index ]
        resources :actuators, only: [ :index ]
      end

      resources :trees, only: [ :show ] do
        get :telemetry, to: "telemetry#tree_history", on: :member
      end

      # Біологічні константи (DNA Registry)
      resources :tree_families

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 📡 НЕЙРОННА МЕРЕЖА (Hardware & Telemetry)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :gateways, only: [ :index, :show ] do
        get :telemetry, to: "telemetry#gateway_history", on: :member
      end

      resources :telemetry, only: [] do
        # Живий потік істини (Matrix Stream)
        get :live, on: :collection, as: :live_stream
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 💎 СКАРБНИЦЯ ТА КОНТРАКТИ (Economy)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :wallets, only: [ :index, :show ]

      resources :contracts, only: [ :index, :show ] do
        get :stats, on: :collection
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⚙️ ВУЗЛИ ВОЛІ (Actuators & Control)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :actuators, only: [ :show ] do
        post :execute, on: :member
      end

      # Аудит виконання команд
      get "actuator_commands/:id", to: "actuators#command_status", as: :actuator_command_status

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🚀 ЕВОЛЮЦІЯ (Firmware & OTA)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :firmwares, only: [ :index, :new, :create ] do
        get  :inventory, on: :collection
        post :deploy,    as: :deploy, on: :member
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⚠️ ОПЕРАЦІЇ ТА РИТУАЛИ (Alerts & Maintenance)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :alerts, only: [ :index, :show ] do
        patch :resolve, on: :member
      end

      resources :maintenance_records, only: [ :index, :create, :show ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⊙ ВИДІННЯ ОРАКУЛА (Strategic Intelligence)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :oracle_visions, only: [ :index ] do
        post :simulate,      on: :collection
        get  :stream_config, on: :collection
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⛓️ БЕЗПЕКА ТА ЕТИКА (Integrity)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :system_audits, only: [ :index ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 📒 БЛОКЧЕЙН ЛЕДЖЕР (The Ledger)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :blockchain_transactions, only: [ :index, :show ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔔 НЕЙРОННА ПАВУТИНА (The Neural Web — Notifications)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get  "notifications/settings",  to: "notifications#settings"
      patch "notifications/settings", to: "notifications#update_settings"

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 📊 АРХІВ (The Archive — Reports)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :reports, only: [ :index ] do
        get :carbon_absorption, on: :collection
        get :financial_summary, on: :collection
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🧠 КАРТА МОЗКУ (The Brain Map — Settings)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resource :settings, only: [ :show, :update ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 👁️ СПОСТЕРІГАЧ (The Watcher — Audit Logs)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :audit_logs, only: [ :index, :show ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 💓 ПУЛЬС СИСТЕМИ (System Health)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :system_health, only: [ :index ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⚡ ІНІЦІАЦІЯ (Provisioning)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :provisioning, only: [ :new ] do
        post :register, on: :collection
      end
    end
  end
end

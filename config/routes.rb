# frozen_string_literal: true

Rails.application.routes.draw do
  # Reveal health status on /up
  get "up" => "rails/health#show", as: :rails_health_check

  # Lookbook component preview browser (development only)
  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  namespace :api do
    namespace :v1 do
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔐 КОНТУР ДОСТУПУ (Authentication)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get    "login",  to: "sessions#new",     as: :login
      post   "login",  to: "sessions#create"
      delete "logout", to: "sessions#destroy", as: :logout

      # M2M Auth (Machine-to-Machine — Gateway/Device authentication via Ed25519)
      post "auth/m2m_token", to: "m2m_auth#create", as: :m2m_token
      post "auth/m2m_token/refresh", to: "m2m_auth#refresh", as: :m2m_token_refresh

      # Скидання пароля (Forgot / Reset Password)
      get  "forgot_password", to: "passwords#new",    as: :forgot_password
      post "forgot_password", to: "passwords#create"
      get  "reset_password",  to: "passwords#edit",   as: :edit_password
      patch "reset_password", to: "passwords#update",  as: :reset_password

      # Безпека акаунту (Account Security / Identity Management)
      get   "account_security",              to: "account_security#show",            as: :account_security
      patch "account_security/mfa",          to: "account_security#toggle_mfa",      as: :account_security_mfa
      patch "account_security/password",     to: "account_security#change_password",  as: :account_security_password
      delete "account_security/identities/:id", to: "account_security#unlink_identity", as: :account_security_identity
      patch  "account_security/identities/:id/lock",   to: "account_security#lock_identity",   as: :lock_account_security_identity
      patch  "account_security/identities/:id/unlock", to: "account_security#unlock_identity",  as: :unlock_account_security_identity

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
        member do
          get :telemetry, to: "telemetry#tree_history"
          get :chronicle
        end
      end

      # Біологічні константи (DNA Registry)
      resources :tree_families, only: [ :index, :show, :new, :create, :edit, :update ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 📡 НЕЙРОННА МЕРЕЖА (Hardware & Telemetry)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :gateways, only: [ :index, :show ] do
        get :telemetry, to: "telemetry#gateway_history", on: :member
        post :telemetry, to: "telemetry#gateway_uplink", on: :member
      end

      resources :telemetry, only: [] do
        # Живий потік істини (Matrix Stream)
        get :live, on: :collection, as: :live_stream
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 💎 СКАРБНИЦЯ ТА КОНТРАКТИ (Economy)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :wallets, only: [ :index, :show ] do
        get :balance, on: :member
        get :metadata, on: :member
      end

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

      resources :maintenance_records, only: [ :index, :new, :create, :show, :edit, :update ] do
        patch :verify,  on: :member
        get   :photos,  on: :member
        resources :photos, only: [ :destroy ],
                  controller: "maintenance_record_photos",
                  as: :maintenance_record_photo
      end

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
      resources :blockchain_transactions, only: [ :index, :show ] do
        get :on_chain, on: :member
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔗 CHAINLINK ORACLE (Decentralized Oracle Callbacks)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :oracle_callbacks, only: [ :create ]

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔔 НЕЙРОННА ПАВУТИНА (The Neural Web — Notifications)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get "notifications/settings",  to: "notifications#settings",        as: :notifications_settings
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
      resource :system_health, only: [ :show ], controller: "system_health"

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⚡ ІНІЦІАЦІЯ (Provisioning)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :provisioning, only: [ :new ] do
        post :register, on: :collection
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 📖 КОДЕКС АРХЕТИПІВ (Codex / Lore Module)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # SSOT: docs/04_05_Codex_Lore_Module.md
      # Phase 1 (Foundation): read-only Atlas (realms + nodes index/show).
      # Subsequent phases add attunements, fractions, matches, discoveries,
      # citations and admin CRUD — registered in their own PRs.
      namespace :codex do
        resources :realms, only: [ :index ]
        # Nodes are addressed by slug (not numeric id) — `to_param` overrides
        # `id`, and the route constraint locks the parameter shape.
        resources :nodes, only: [ :index, :show ], param: :slug,
                  constraints: { slug: %r{[a-z0-9][a-z0-9-]*} } do
          # Phase 2 — Community layer.
          resources :attunements, only: [ :create ]
          delete "attunements/me", to: "attunements#destroy_me",
                 as: :my_attunement
          resources :comments, only: [ :create ]
        end
      end
    end
  end
end

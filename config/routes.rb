# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  # Reveal health status on /up
  get "up" => "rails/health#show", as: :rails_health_check

  # Readiness probe (DB + Redis) for orchestrators — unauthenticated, 503 when a dep is down.
  get "ready" => "readiness#show", as: :readiness_check

  # Lookbook component preview browser (development only)
  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  # [ARCH.61] Sidekiq Web UI — ops-інструмент DeadSet-runbook'ів (06_03 §2.8).
  # Sidekiq::Web = Rack-app поза BaseController-auth → route-constraint =
  # ЄДИНИЙ шлюз (HAProxy path-ACL нема): дзеркало admin_or_above? + SEC.16
  # salt-bound cookie. Unmatched → 404 (шлях не розкривається, rack_attack
  # fail2ban банить проби). CSRF вбудований у Sidekiq 8.
  mount Sidekiq::Web => "/sidekiq", :constraints => lambda { |req|
    user = User.find_by(id: req.session[:user_id])
    user.present? &&
      req.session[:ps].to_s == user.password_salt.to_s.last(10) &&
      (user.role_admin? || user.role_super_admin?)
  }

  namespace :api do
    namespace :v1 do
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # 🔐 КОНТУР ДОСТУПУ (Authentication)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      get    "login",  to: "sessions#new",     as: :login
      post   "login",  to: "sessions#create"
      delete "logout", to: "sessions#destroy", as: :logout

      # 🌐 LOCALE SWITCHER — persists UI language in a permanent cookie.
      # Public (unauthenticated visitors on /login also need to switch).
      post "locale", to: "locales#update", as: :locale

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
      resources :organizations, only: [ :index, :show ] do
        post :switch, on: :member
      end

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
        # [UI.6] БЕЗ `as:` — вкладений `resources` уже дає префікс `api_v1_maintenance_record_`,
        # тож `as: :maintenance_record_photo` доклеював його ВДРУГЕ й давав хелпер
        # `api_v1_maintenance_record_maintenance_record_photo_path`, якого не кликав ніхто.
        # Єдиний викликач (`PhotoCard#render_delete_button`) писався під природне ім'я і був
        # правий — тобто ламав маршрут, а не компонент, і сторінка запису з будь-яким фото
        # падала в `NoMethodError` → 500.
        resources :photos, only: [ :destroy ], controller: "maintenance_record_photos"
      end

      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      # ⊙ ВИДІННЯ ОРАКУЛА (Strategic Intelligence)
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      resources :oracle_visions, only: [ :index ] do
        post :simulate, on: :collection
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
      # 🆘 HELIUM SOS (ARCH.34 L3 — Королева кричить через чужі hotspot'и)
      # Webhook Helium Console HTTP Integration; HMAC-патерн oracle_callbacks.
      # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
      post "telemetry/helium", to: "helium_sos#create"

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
          delete "attunements/me", to: "attunements#destroy",
                 as: :my_attunement
          resources :comments, only: [ :create ]
        end

        # Phase 3 — Identity layer. One active fraction per user (UNIQUE
        # user_id at DB level). The collection POST handles both initial
        # pick and re-pick; cooldown is enforced by the service.
        resources :fractions, only: [ :create ]
        get  "fractions/me",     to: "fractions#show",   as: :my_fraction
        get  "fractions/picker", to: "fractions#picker", as: :fraction_picker

        # Phase 4 — Battle layer. The resource is `Codex::Match`; the
        # "Battle Arena" name is a UX label, not a REST noun.
        # `new` returns the next pair to vote on (Turbo Frame Arena).
        # `create` records the vote (or skip).
        resources :matches, only: [ :new, :create ]
        get "leaderboard",  to: "leaderboard#index", as: :leaderboard

        # Phase 5 — Discovery layer. End-users only read their own
        # collection; unlocks happen via `Codex::DiscoveryProbeWorker`,
        # never via an end-user POST.
        get "discoveries/me", to: "discoveries#index", as: :my_discoveries

        # Phase 6 — Cross-domain stitch. Citations are forester+ create,
        # own/admin+ destroy. Read happens in-line in target view
        # components (Tree::Show, Cluster::Show, ForecastCard, Alerts::Row)
        # via `Citation.bulk_for(targets)` — no read endpoint needed.
        resources :citations, only: [ :create, :destroy ]

        namespace :admin do
          # ⚠️ `only:` тут несуче, а не гігієна [ARCH.77]: обидва контролери —
          # чисто-JSON і форм не мають, тож без обмеження Rails генерував
          # `new`/`edit`, які вели в `ActionNotFound`. Той виняток кидається в
          # `AbstractController::Base#process` ДО `process_action`, тобто повз
          # `rescue_from StandardError` — і Rails мапить його на 404, а не 500.
          # Тихий наслідок: кожне таке звернення інкрементить fail2ban-лічильник
          # (він рахує 401/404), тобто мертвий маршрут ще й годував бан.
          # DAO-editable unlock-rule registry. `admin_or_above?` only.
          resources :discovery_rules, only: %i[index show create update destroy]
          # Phase 6 — DAO node curation. Create restricted to super_admin
          # in `Codex::Admin::NodePolicy`; update/destroy admin+.
          resources :nodes, param: :slug, only: %i[index show create update destroy],
                    constraints: { slug: %r{[a-z0-9][a-z0-9-]*} }
        end
      end
    end
  end
end

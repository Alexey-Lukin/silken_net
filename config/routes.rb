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
    user&.session_salt_matches?(req.session[:ps]) &&
      (user.role_admin? || user.role_super_admin?)
  }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # 🤖 МАШИННИЙ КОНТУР — /api/v1 (ARCH.77)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # Тут живе рівно те, чийого КЛІЄНТА відвантажуємо не ми: прошивка в полі,
  # чужа консоль, чужий оракул. Саме там версія в шляху щось значить — клієнт
  # не оновлюється разом із деплоєм. Браузерний контур (нижче) її не має й не
  # потребує: його клієнт приходить із кожною відповіддю сервера.
  #
  # ⚠️ Це НЕ «JSON проти HTML»: більшість браузерних екшенів теж віддають JSON.
  # Критерій — ХТО відвантажує клієнта, і лише він.
  #
  # `v2` тут не планується (⚖️ founder 2026-08-01 — won't-do): при потребі
  # версіонують ФОРМАТ (як CoAP-тракт: `QATT_VERSION_2`, `wire-rev2.1`,
  # `silken.mrv.lineage.v1`), а не переписують дерево маршрутів.
  namespace :api do
    namespace :v1 do
      # M2M Auth (Machine-to-Machine — Gateway/Device authentication via Ed25519)
      post "auth/m2m_token", to: "m2m_auth#create", as: :m2m_token
      post "auth/m2m_token/refresh", to: "m2m_auth#refresh", as: :m2m_token_refresh

      # 🔗 CHAINLINK ORACLE — DON callback (HMAC `X-Chainlink-Signature`)
      resources :oracle_callbacks, only: [ :create ]

      # 🆘 HELIUM SOS (ARCH.34 L3 — Королева кричить через чужі hotspot'и)
      # Webhook Helium Console HTTP Integration; HMAC-патерн oracle_callbacks.
      # ⚠️ Адреса їде у ЧУЖУ консоль (terraform/akash: «Also entered in Helium
      # Console HTTP Integration») — міняти лише разом із нею.
      post "telemetry/helium", to: "helium_sos#create"

      # HTTP Telemetry Uplink — запасний канал, коли CoAP/UDP заблоковано
      # (Phase 3 ESP32-міст). Читання тієї ж телеметрії — браузерне, живе на
      # корені (`telemetry#gateway_history`).
      post "gateways/:id/telemetry", to: "telemetry#gateway_uplink",
           as: :gateway_telemetry_uplink
    end
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # 🌿 БРАУЗЕРНИЙ КОНТУР — кореневі шляхи (ARCH.77)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # `module:` лишає контролери фізично в `app/controllers/api/v1/**` — це
  # ВНУТРІШНЯ організація файлів, не адреса. Зняти цей рядок = окрема дешева
  # операція, вона нічого не змінює зовні.
  scope module: "api/v1" do
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # 🔐 КОНТУР ДОСТУПУ (Authentication)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    get    "login",  to: "sessions#new",     as: :login
    post   "login",  to: "sessions#create"
    # [S6.21] Другий фактор: pending-мітка з sessions#create веде сюди; сесії до
    # verify не існує, тож шлях живе в auth-зоні (skip authenticate_user!).
    get    "login/mfa", to: "mfa_challenges#new", as: :mfa_challenge
    post   "login/mfa", to: "mfa_challenges#create"
    delete "logout", to: "sessions#destroy", as: :logout

    # 🌐 LOCALE SWITCHER — persists UI language in a permanent cookie.
    # Public (unauthenticated visitors on /login also need to switch).
    post "locale", to: "locales#update", as: :locale

    # Скидання пароля (Forgot / Reset Password)
    get  "forgot_password", to: "passwords#new",    as: :forgot_password
    post "forgot_password", to: "passwords#create"
    get  "reset_password",  to: "passwords#edit",   as: :edit_password
    patch "reset_password", to: "passwords#update",  as: :reset_password

    # Безпека акаунту (Account Security / Identity Management)
    get   "account_security",              to: "account_security#show",            as: :account_security
    # [SEC.18] DSAR self-service: субʼєкт качає ВЛАСНІ дані (Art.15/20)
    get   "account_security/data_export",  to: "account_security#data_export",     as: :account_security_data_export
    # [SEC.18] Art.17 erasure self-service. DELETE, бо акт незворотний і знищує
    # ресурс; step-up на пароль стоїть у контролері (⚖️ founder 2026-08-21).
    delete "account_security/erase",       to: "account_security#erase_account",   as: :account_security_erase
    patch "account_security/mfa",          to: "account_security#toggle_mfa",      as: :account_security_mfa
    # [S6.21] Setup-флоу TOTP: провижн (POST) → QR-сторінка (GET) → активація (PATCH).
    get   "account_security/mfa_setup",    to: "mfa_setups#show",                  as: :mfa_setup
    post  "account_security/mfa_setup",    to: "mfa_setups#create"
    patch "account_security/mfa_setup",    to: "mfa_setups#update"
    # [S6.21] Одноразовий показ recovery-набору (GET, session-маркер) + ротація
    # набору (POST на ТОЙ САМИЙ шлях — create-семантика нового набору, без
    # окремого breadcrumb-сегмента).
    get  "account_security/mfa_recovery_codes", to: "mfa_setups#recovery_codes", as: :mfa_recovery_codes
    post "account_security/mfa_recovery_codes", to: "mfa_setups#rotate_recovery_codes"
    patch "account_security/password",     to: "account_security#change_password",  as: :account_security_password

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # 🏰 ЦЕНТРАЛЬНИЙ ВІВТАР (Dashboard)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    resources :dashboard, only: [ :index ]
    # [ARCH.77] Корінь застосунку тепер СПРАВДІ корінь: `root_path` існує, і
    # `redirect_to root_path` більше не кидає NoMethodError (клас UI.6).
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
    # ⚠️ Лише ЧИТАННЯ. Запис (uplink від Королеви) — машинний контур вище:
    # той самий шлях, інше дієслово, інший відвантажувач клієнта.
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
    resources :wallets, only: [ :index, :show ] do
      get :balance, on: :member
      get :metadata, on: :member
      # [UI.7] CSV-вивантаження леджера; `defaults` тримає формат і на голому GET,
      # інакше запит без розширення падав би в 406 замість файла.
      get :ledger, on: :member, defaults: { format: :csv }
    end

    # [I18N.2 · клас 2] Комірка статусу транзакції, яку глядач тягне СВОЇМ запитом —
    # тобто вже у своїй локалі. Пласка форма, як у сусіда `actuator_commands/:id`:
    # вкладений `resources` дав би той самий шлях довшою дорогою. Скоуп навмисно
    # через ГАМАНЕЦЬ: сторінка вже авторизувала саме цей обʼєкт, тож ендпоінт
    # переспитує ТЕ САМЕ право (`WalletPolicy#transaction_status? = show?`) і не
    # заводить другого правила тенантності, яке могло б розійтися зі сторінкою.
    get "wallets/:wallet_id/transactions/:id/status",
        to: "wallets#transaction_status",
        as: :wallet_transaction_status

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
      # [UI.6] БЕЗ `as:` — вкладений `resources` уже дає префікс
      # `maintenance_record_`, тож `as: :maintenance_record_photo` доклеював
      # би його ВДРУГЕ й давав хелпер, якого не кличе ніхто. Єдиний викликач
      # (`PhotoCard#render_delete_button`) писався під природне ім'я і був
      # правий — тобто ламав маршрут, а не компонент, і сторінка запису з
      # будь-яким фото падала в `NoMethodError` → 500.
      resources :photos, only: [ :destroy ], controller: "maintenance_record_photos"
    end

    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    # ⊙ ВИДІННЯ ОРАКУЛА (Strategic Intelligence)
    # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    resources :oracle_visions, only: [ :index ]

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
    # ⚠️ Браузерний, попри назву: `authorize_forester!` + Phlex-форма, а
    # `register` віддає `format.html`. Машинного клієнта не існує — фабричний
    # тракт (`03_06`) ходить rake-задачами у власному процесі, не HTTP.
    resources :provisioning, only: [ :new ] do
      post :register, on: :collection
    end
  end
end

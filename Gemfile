source "https://rubygems.org"

ruby "4.0.6"
gem "rails", "~> 8.1.3"

gem "aasm"
gem "active_storage_validations"
gem "argon2id"
gem "aws-sdk-s3", require: false
gem "blueprinter"
gem "bootsnap", require: false
gem "csv"
gem "ed25519"
gem "eth"
gem "google-cloud-storage", require: false   # Active Storage: Google Cloud Storage (mirror / disaster recovery)
gem "httpx"
gem "image_processing"
gem "importmap-rails"
gem "kamal", require: false
gem "kredis"
gem "oj"
gem "pagy"
gem "pg"
gem "phlex-rails"
gem "prawn"
gem "prawn-table"
gem "prometheus-client"
gem "propshaft"
gem "puma"
gem "pundit"
gem "rack-attack"
# Базовий шар перекладів Rails (errors/date/number + правила плюралізації).
# Мусить лишатись у ГОЛОВНІЙ групі: транзитивна присутність у Gemfile.lock ≠
# завантаження — деталь і пастка в `docs/04_04 §12.2`.
gem "rails-i18n"
# [S6.21] TOTP другий фактор (RFC 6238): чистий Ruby, нуль залежностей,
# нуль нативних розширень; 6.3.0 = 2023-08-30, три роки зрілості.
gem "rotp"
# [S6.21] QR для provisioning URI (SVG, без ImageMagick); core — той самий реліз-цикл.
gem "rqrcode"
# Двигун vips-трансформера (`config.active_storage.variant_processor = :vips`):
# image_processing тримає ruby-vips опціональним, тож без явного гема трансформера
# просто не існує. Active Storage требує його при буті, щоб вимкнути unfuzzed-лоадери
# libvips — потрібні libvips ≥ 8.13 (Dockerfile, CI) та ruby-vips ≥ 2.2.1.
gem "ruby-vips", require: false
gem "rumale"
gem "sentry-rails"
gem "sentry-ruby"
gem "sentry-sidekiq"
gem "sidekiq"
gem "sidekiq-scheduler"
gem "solid_cable"
gem "solid_cache"
gem "stimulus-rails"
gem "strong_migrations"
gem "tailwindcss-rails"
gem "tailwind_merge"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "factory_bot_rails"
  # Catches missing translations across all shipped locales (en/uk/lv/lt —
  # config/i18n-tasks.yml). Runs in CI as a hard gate (`i18n-tasks missing`,
  # ci.yml i18n_check) so a PR that adds a key in one locale but forgets the
  # others fails the build. `health` свідомо НЕ ганяємо: його unused-половина
  # хибно спрацьовує на динамічних лукапах (navigation.items.*, filter_*).
  gem "i18n-tasks", require: false
  gem "pg_query"
  gem "prosopite"
  gem "rspec-rails"
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", require: false
end

group :development do
  gem "dotenv-rails"
  gem "lookbook"
  gem "view_component"
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "cuprite"
  # [UI.3, ⚖️ 2026-08-20] Advisory axe-прогін (НЕ HARD): рушій той самий, що в
  # Lighthouse (Deque, MPL-2.0 — file-level copyleft, наш код не зачіпає).
  # Runtime-ланцюг виміряно перед внесенням: axe-core-api → dumb_delegator,
  # selenium ЛИШЕ в development_dependencies самого гема; адаптери duck-typing'ом
  # беруть Capybara-сесію через evaluate_script — тобто наш Ferrum/CDP-стек.
  gem "axe-core-rspec"
  # [TEST.8] `parallel_tests` знято 2026-08-03: гем приїхав ботом разом із Cuprite
  # і НІКОЛИ не був задротований (нуль `TEST_ENV_NUMBER` у `database.yml`/CI/bin).
  # Після того, як `rails_helper` зацементував «другий прогін = помилка», його
  # присутність робила дерево двоголосим. Паралельність тут і не потрібна: повна
  # сюїта ~1.5 хв при `timeout-minutes: 15`, а кожна CI-джоба має власні
  # postgis+valkey. Знадобиться — вертати разом із БД-на-процес, не самим гемом.
  gem "simplecov", require: false
end

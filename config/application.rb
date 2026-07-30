# SPDX-License-Identifier: AGPL-3.0-or-later
require_relative "boot"

# ⚠️ ПОРЯДОК НЕСУЧИЙ, не алфавіт. `rails/all` тягне activestorage/engine.rb, а той
# у тілі класу згадує `ImageAnalyzer::Vips` → autoload → ruby-vips → glib. Якщо glib
# заходить ПЕРШОЮ, нативний argon2id ламається на arm64-darwin: `__stack_chk_fail`
# у `initial_hash`, SIGABRT (134) на ~50 хешах. Зворотний порядок чистий, тож
# argon2id вантажимо до rails/all. Мінімальний репро (без Rails):
#   ruby -e 'require "ruby-vips"; require "argon2id"; 50.times { Argon2id::Password.create("p") }'  → 134
#   ruby -e 'require "argon2id"; require "ruby-vips"; …'                                            → 0
# Linux (CI/Docker) не відтворює — тримаємо рядок для локальної сюїти на macOS.
require "argon2id"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SilkenNet
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets daemons tasks])

    # [KENOSIS TITAN]: structure.sql зберігає партиціювання PostgreSQL (schema.rb не підтримує)
    config.active_record.schema_format = :sql

    # [I18N]: Quadrilingual UI (EN default; UA/LV/LT auto-detected via
    # Accept-Language header, or saved via locale cookie). Locale files are
    # organised by domain under config/locales/<group>/<locale>.yml — the
    # nested load_path picks them up automatically. New languages are added
    # by appending to `available_locales` and shipping a matching YAML set.
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
    config.i18n.available_locales = %i[uk en lv lt]
    config.i18n.default_locale    = :en
    # Локаль-НЕЗАЛЕЖНИЙ ланцюг: `true` → railtie будує `Fallbacks.new(default_locale)`,
    # тобто хвіст `[:en]` для БУДЬ-ЯКОЇ локалі — і наявної, і майбутньої, і
    # регіональної (`pt-BR` → `[:pt-BR, :pt, :en]` через parent-ланцюг). Поіменний
    # хеш, що стояв тут раніше, був єдиною формою з ПОРОЖНІМ `defaults`: нова
    # локаль не діставала `:en` взагалі, а `production.rb` це мовчки перекривав
    # своїм `= true` — тобто dev/test і прод розходились. Дім пояснення — `04_04 §12.2`.
    config.i18n.fallbacks         = true

    # [GAIA SHIELD]: Rack::Attack — DDoS / brute-force / bot-scanner protection.
    # Inserted early in the middleware stack so malicious traffic is dropped
    # before it reaches ActionDispatch, Warden or ActiveRecord.
    config.middleware.use Rack::Attack

    # [OBSERVABILITY]: Prometheus /metrics endpoint — secured by IP allowlist
    # and optional HTTP Basic Auth. Inserted early so it short-circuits before
    # routing, session handling, or CSRF protection.
    require_relative "../app/middleware/prometheus_collector"
    config.middleware.use PrometheusCollector

    # [PUMA-IO-1]: Mark Web3-heavy endpoints (oracle_callbacks, provisioning)
    # as IO-bound for Puma 8.0+ thread pool, so slow third-party RPC calls
    # don't starve the worker. Inserted AFTER PrometheusCollector so /metrics
    # scrapes are not flagged. See docs/06_05_Puma_Configuration.md.
    require_relative "../app/middleware/mark_web3_requests_as_io_bound"
    config.middleware.use MarkWeb3RequestsAsIoBound

    # Phlex components & layouts: autoload app/views/components and
    # app/views/layouts so Wallets::TransactionRow, DashboardLayout, etc.
    # are resolvable by Zeitwerk without the Views:: wrapper.
    config.autoload_paths << root.join("app/views/components").to_s
    config.autoload_paths << root.join("app/views/layouts").to_s

    # Use RSpec and FactoryBot for generators
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end

    # Prepend a custom PostgreSQL bin path to PATH if configured via POSTGRES_BIN_PATH.
    # Useful when multiple PG versions are installed and the server version differs from
    # the default pg_dump/psql binaries in PATH (e.g. PG17 server, PG16 client in PATH).
    # Set POSTGRES_BIN_PATH in .env or .env.development.local (gitignored).
    if (pg_bin = ENV["POSTGRES_BIN_PATH"]).present? && !ENV["PATH"].to_s.include?(pg_bin)
      ENV["PATH"] = "#{pg_bin}:#{ENV["PATH"]}"
    end

    # Lookbook component previews path
    config.lookbook.preview_paths = [ root.join("spec/components/previews").to_s ] if defined?(Lookbook)
  end
end

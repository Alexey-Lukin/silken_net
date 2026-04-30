require_relative "boot"

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

    # Lookbook component previews path
    config.lookbook.preview_paths = [ root.join("spec/components/previews").to_s ] if defined?(Lookbook)
  end
end

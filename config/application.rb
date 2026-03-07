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
  end
end

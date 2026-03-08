# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Sidekiq: перехоплює perform_async в пам'ять — Redis не потрібен для тестів
# New API (Sidekiq 8.1.1+): https://github.com/sidekiq/sidekiq/wiki/Testing#new-api
Sidekiq.testing!(:fake)

# Ensures that the test database schema matches the current schema file.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Use transactional fixtures — each example is wrapped in a transaction that
  # is rolled back afterwards, keeping the database clean between examples.
  config.use_transactional_fixtures = true

  # Infer spec type from file location (e.g. spec/models → type: :model).
  config.infer_spec_type_from_file_location!

  # Remove Rails internals from backtraces for cleaner failure output.
  config.filter_rails_from_backtrace!

  # Honour :focus tag so that `fit` / `fdescribe` / `fcontext` work here too.
  config.filter_run_when_matching :focus

  # Clear Sidekiq queues before each example so jobs don't bleed between tests.
  config.before(:each) do
    Sidekiq::Job.clear_all
  end

  # FactoryBot shorthand: create(:user) instead of FactoryBot.create(:user)
  config.include FactoryBot::Syntax::Methods

  # ActiveSupport time helpers: travel_to, freeze_time, etc.
  config.include ActiveSupport::Testing::TimeHelpers
end

# Load support files (Cuprite config, shared contexts, etc.)
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

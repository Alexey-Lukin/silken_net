# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

# Sidekiq: перехоплює perform_async в пам'ять — Redis не потрібен для тестів
require 'sidekiq/testing'
Sidekiq::Testing.fake!

# Ensures that the test database schema matches the current schema file.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Очищуємо чергу Sidekiq перед кожним тестом, щоб тести не впливали один на одного
  config.before(:each) do
    Sidekiq::Job.clear_all
  end

  # FactoryBot shorthand: create(:user) instead of FactoryBot.create(:user)
  config.include FactoryBot::Syntax::Methods

  # ActiveSupport time helpers: travel_to, freeze_time, etc.
  config.include ActiveSupport::Testing::TimeHelpers
end

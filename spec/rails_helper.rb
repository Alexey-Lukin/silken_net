# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
# [SEC.11] PROVISIONING_MASTER_KEY is required by HardwareKeyService and
# SilkenNet::SeedDerivation — there is no SecureRandom fallback. Pin a
# stable test-mode value so the whole suite shares deterministic AES /
# K_seed derivation.
ENV["PROVISIONING_MASTER_KEY"] ||= "silken-net-test-master-key-32b!!"
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
  # Clear Rails cache so rate-limit counters and silence filters don't leak across examples.
  # Flush Kredis Redis (DB 1) to remove nonce keys (M2M replay, distributed locks) between tests.
  config.before do
    Sidekiq::Job.clear_all
    Rails.cache.clear
    # [SEC.22] Derived-key cache is keyed by (info, uid) without a master-key
    # version → clear it so a seed derived under one example's ENV master key
    # never bleeds into the next (the `config.around` below restores ENV itself).
    DERIVED_KEY_CACHE.clear
    Rack::Attack.cache.store.clear
    Rack::Attack.reset!
    Web3::RpcConnectionPool.reset!
    begin
      Kredis.redis(config: :shared).flushdb
    rescue RedisClient::CannotConnectError, Redis::CannotConnectError, RedisClient::ConnectionError, Errno::ECONNREFUSED
      # Redis may not be available in CI — safe to skip flush
    end
  end

  # Reset I18n.locale between examples — the LocalesController#update endpoint
  # mutates I18n.locale globally (Thread-local), so without this reset a single
  # POST /api/v1/locale spec leaks the locale into every subsequent example
  # that doesn't explicitly wrap itself in I18n.with_locale.
  #
  # Use `after` (not `before`) so per-example `around { I18n.with_locale(:uk) }`
  # blocks remain in force during the example — `around` wraps `before`/`after`
  # hooks, so a `before { I18n.locale = ... }` would override the around block
  # and break specs that locked themselves to a specific locale.
  config.after do
    I18n.locale = I18n.default_locale
  end

  # [TEST.2] Snapshot + restore ENV around every example. Чимало спеків мутують
  # ENV напряму (feature-флаги, ORACLE-ключі, SOLANA_*, STRESS_*…) без restore
  # або з restore через `after`/inline — а той біжить РАНІШЕ за тіардаун
  # `stub_const("ENV", …)`, тож чистить стаблений Hash, а реальна змінна тече в
  # наступні приклади (саме так утік TELEMETRY_CCM_ENABLED → chunk_size 29 → 21-
  # байтні пакети тихо скіпались). `around`-ensure відпрацьовує ПІСЛЯ тіардауну
  # стабу, на реальному ENV, тож `ENV.replace` надійно відкочує per-example
  # мутації. Змінні з before(:all)/suite живуть далі — вони в snapshot.
  config.around do |example|
    env_snapshot = ENV.to_h
    example.run
  ensure
    ENV.replace(env_snapshot)
  end

  # Prosopite: N+1 query detection in request specs.
  # Raises Prosopite::NPlusOneQueriesError when duplicate queries detected.
  config.before(:each, type: :request) do
    Prosopite.scan if defined?(Prosopite)
  end

  config.after(:each, type: :request) do
    Prosopite.finish if defined?(Prosopite)
  end

  # FactoryBot shorthand: create(:user) instead of FactoryBot.create(:user)
  config.include FactoryBot::Syntax::Methods

  # ActiveSupport time helpers: travel_to, freeze_time, etc.
  config.include ActiveSupport::Testing::TimeHelpers
end

# Load support files (Cuprite config, shared contexts, etc.)
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

# SPDX-License-Identifier: AGPL-3.0-or-later
# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :memory_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Use inline job processing so Sidekiq workers execute immediately in tests.
  config.active_job.queue_adapter = :test

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Reduce noise in test output — show only warnings and errors.
  config.log_level = :warn

  # No need to dump schema after migrations in test environment.
  config.active_record.dump_schema_after_migration = false

  # ActiveRecord Encryption — deterministic test-only keys.
  # These values are safe to commit: they are never used outside the test env.
  config.active_record.encryption.primary_key        = "test-primary-key-silken-net-32b!"
  config.active_record.encryption.deterministic_key  = "test-determin-key-silken-net-32!"
  config.active_record.encryption.key_derivation_salt = "test-derivation-salt-silknet32b!"

  # 🔴 [TEST.8] Третій носій того ж класу — і він для процесу, який НЕ є сюїтою.
  # Два гарди в `spec/rails_helper.rb` живуть у `before(:suite)`, тобто бачать
  # лише rspec. А забруднювачем у цьому дереві двічі був `bin/rails runner`:
  # він пише повз транзакційні фікстури (лишаючи записане навіть коли падає далі),
  # а зачистка Kredis сюїти вимиває ЙОГО `silken:*`-ключі перед кожним прикладом — тож
  # запущена під час прогону проба ще й БРЕШЕ у відповідь. Правило «обгортай
  # runner у rollback-транзакцію» записане в `04_06 §B.2` #16, але записане
  # правило не стріляє: воно існує лише там, де в момент дії стоїть перевірка.
  #
  # ⚠️ Свідомо WARN, не raise: на відміну від сюїти, разова проба може бути
  # цілком легітимною (діагностика того самого прогону), і fail-closed тут бив би
  # по тому, кого не захищає. Шумом це не стане — умова істинна лише поки реально
  # біжить чужа сюїта.
  config.after_initialize do
    next if $PROGRAM_NAME.end_with?("rspec") || defined?(RSpec::Core::Runner)

    owner = begin
      Kredis.redis(config: :shared).get("rspec:suite_owner_pid")
    rescue StandardError
      nil
    end
    next if owner.blank?

    warn <<~MSG
      \e[33m⚠️  У цій же test-БД зараз біжить rspec-сюїта (pid #{owner}).\e[0m
         · твої записи переживуть її прогін і зачервонять наступний
           (гард брудної БД тоді назве таблиці, але ЦЕ вже сталося);
         · зачистка Kredis сюїти вимиває твої `silken:*`-ключі перед кожним її прикладом,
           тож усе, що ти зараз поміряєш у Redis, буде НЕПРАВДОЮ.
         Безпечна форма: ActiveRecord::Base.transaction { …; raise ActiveRecord::Rollback }
    MSG
  end
end

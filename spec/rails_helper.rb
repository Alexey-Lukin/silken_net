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

# [TEST.8] Ключ-власник прогону в тому ж Redis, що й Kredis — тобто рівно там, де
# конкуренція двох прогонів і шкодить.
# 🔴 [INF.22] Ім'я НЕ несе префікса `silken:` СВІДОМО: зачистка між прикладами —
# це `Kredis.clear_all`, а він видаляє лише `<namespace>:*`, тож ключ переживає
# власну сюїту. Доти тут стояв `flushdb`, який стирав його разом з усім, і саме
# тому нижче є рядок, що мітку ПЕРЕставляє — його підстава відпала, лишилось
# продовження TTL. Даси цьому ключу префікс — і гард конкуренції знову почне
# вимикати сам себе, мовчки.
SUITE_OWNER_KEY = "rspec:suite_owner_pid"

# Чи живий процес-власник. Без цієї перевірки вбитий прогін (Ctrl-C, краш) лишав
# би ключ до кінця TTL і блокував НАСТУПНИЙ чесний прогін — fail-closed там, де
# ціна помилки лише зручність, коштує дорожче за проблему, яку лікує.
# `Process.kill(0, pid)` не шле сигналу, а лише перевіряє існування й доступ;
# EPERM означає «процес є, але чужий» — теж живий.
def process_alive?(pid)
  Process.kill(0, Integer(pid))
  true
rescue Errno::ESRCH, ArgumentError, TypeError
  false
rescue Errno::EPERM
  true
end

RSpec.configure do |config|
  # Use transactional fixtures — each example is wrapped in a transaction that
  # is rolled back afterwards, keeping the database clean between examples.
  config.use_transactional_fixtures = true

  # 🔴 [TEST.8] Транзакційні фікстури ізолюють приклади ОДИН ВІД ОДНОГО — і нічого
  # не кажуть про рядки, що лежали в БД ДО прогону. `bin/rails runner` у
  # `RAILS_ENV=test` пише повз них, і навіть впавши на валідації лишає те, що
  # встиг записати ДО падіння.
  #
  # Виміряно 2026-08-03 (чотири залишкові рядки, той самий коміт і харнес):
  # чиста БД — `0 failures`; та сама сюїта на бруді — **26 падінь у 13 файлах**.
  # Механізмів ДВА, і саме другий робить симптом схожим на порядко-залежний флак:
  #   · глобальний лік у твердженні (`BlockchainTransaction.where(…).count == 1`)
  #     падає завжди, від сіда не залежить;
  #   · колізія FactoryBot-послідовності (вона стартує з 1 у КОЖНОМУ процесі)
  #     валить той приклад, який першим витягне вже зайняте значення — а це
  #     вирішує ПОРЯДОК, тож у ізоляції файл зелений.
  # На тому самому бруді сіди 11111/22222 дали 26 і 25 падінь із сімома різними.
  # Тобто «різні сіди — різне число падінь» доводить брудну БД рівно так само
  # добре, як витік стану між прикладами, і два проходи діагностики пішли не туди
  # саме тому, що ця розвилка ніде не була названа.
  #
  # ⚠️ Стеля, названа явно (мовчання тут читалося б як «перевірено все»): гард
  # бачить лише те, що лежить на СТАРТІ прогону. Рядок, записаний повз транзакцію
  # ВСЕРЕДИНІ сюїти, для нього не існує, як і будь-який бруд у Redis.
  # 🔴 [TEST.8] ДРУГИЙ носій того самого класу, і виміряно, що саме він — головний.
  # Транзакційні фікстури ізолюють приклади всередині ОДНОГО процесу; про ДРУГИЙ
  # процес вони не знають нічого, а спільного мутабельного стану між прогонами
  # рівно два — Redis (`Kredis.clear_all` нижче біжить перед КОЖНИМ прикладом, тобто
  # чужий прогін вимиває твої ключі посеред твого ж приклада) і сама Postgres.
  #
  # Вимір 2026-08-03 на ЧИСТІЙ БД: соло-прогін — `0 failures`; два одночасні —
  # **17 і 19 падінь**, і трійка найчастіших жертв збіглася з трійкою, названою в
  # пункті, до файла (`batch_payout_service` · `vote_recorder_service` ·
  # `unpack_telemetry_worker_attest`). Механізмів теж два: `seed_invalid_or_consumed`
  # (чужий `flushdb` зʼїв виданий сид) і `PG::TRDeadlockDetected` на вставці дерев.
  # Це пояснює вихідне спостереження краще за брудну БД: «в ізоляції зелено» —
  # бо соло; «на різних сідах то 0, то 5, то 8» — бо число залежить від того,
  # наскільки прогони перекрились у ЧАСІ, а не від сіда.
  #
  # ⚠️ У CI гард мовчить за побудовою: обидві джоби, що звуть rspec (`test`,
  # `feature-test`), оголошують ВЛАСНІ `postgis`+`valkey`-сервіси, а Actions
  # ізолює їх по джобах — ключа там просто не існує.
  #
  # ⚠️ Стеля, і вона не косметична: гард ключиться на Redis, а ділять прогони ДВА
  # ресурси. Хто ізолює лише Redis (`KREDIS_REDIS_URL` на ОКРЕМИЙ інстанс — номер
  # бази для цього більше не годиться, [INF.22]), той гард приглушить,
  # а `PG::TRDeadlockDetected` на спільній Postgres лишиться — справжня
  # паралельність вимагає окремої БД на процес (`parallel_tests`-модель), і це
  # інша робота, ніж ця перевірка. Плюс гард бачить лише прогони, що дійшли до
  # цього хука, і не бачить того, хто стартував за мілісекунду до нього.
  #
  # ⚠️ Четверта стеля, і вона найтихіша: гард живе в ЦЬОМУ файлі, а колізійний
  # прогін може його не вантажити взагалі. `spec/lib/docs_*_spec.rb` вимагають
  # лише `spec_helper` (pure-unit, без Rails), тож смуга Docs, що кличе їх через
  # `COVERAGE=0 bin/rspec`, до цього хука не доходить ЖОДНОГО разу. Ділили вони
  # з повною сюїтою не БД, а `coverage/.resultset.json`.
  # ✅ **[TEST.15, 2026-08-13] Цю половину знято в корені:** `COVERAGE=0` тепер
  # вимикає сам ЗАПИС (SimpleCov не стартує), а не лише поріг — доти цей коментар
  # чесно фіксував розбіжність «гейт ⊥ запис» як данність, і вона крала сесію
  # чотири рази підпис колізії `0 failures` при EXIT=2 і групи по 0.0 %.
  # Носій — `scripts/docs_band.rb` (відбиток resultset до/після кроків).
  # ⚠️ Стеля лишається: гард нижче все одно не бачить прогону, що не вантажить
  # цей файл, — просто такий прогін більше не має чим зашкодити.
  config.before(:suite) do
    redis = Kredis.redis(config: :shared)
    owner = redis.get(SUITE_OWNER_KEY)

    if owner.present? && owner != Process.pid.to_s && process_alive?(owner)
      raise <<~MSG
        \n🔴 у цій же Redis-БД уже біжить інша rspec-сюїта (pid #{owner}).
        Два прогони НЕ ізольовані: зачистка Kredis перед кожним прикладом вимиває
        ключі чужого процесу, а Postgres дає дедлоки на конкурентних вставках.
        Виміряно: соло — 0 падінь, два одночасні — 17 і 19.

        Зачекай на той прогін, або, якщо він мертвий:
          RAILS_ENV=test bin/rails runner 'Kredis.redis(config: :shared).del("#{SUITE_OWNER_KEY}")'
      MSG
    end

    redis.set(SUITE_OWNER_KEY, Process.pid, ex: 2.hours.to_i)
  rescue RedisClient::CannotConnectError, Redis::CannotConnectError,
         RedisClient::ConnectionError, Errno::ECONNREFUSED
    # Redis може бути недоступний (як і для flush нижче) — тоді конкурентні
    # прогони й так не ділять Kredis, а мовчання чесніше за фальшиву тривогу.
    nil
  end

  config.after(:suite) do
    Kredis.redis(config: :shared).del(SUITE_OWNER_KEY)
  rescue RedisClient::CannotConnectError, Redis::CannotConnectError,
         RedisClient::ConnectionError, Errno::ECONNREFUSED
    nil
  end

  config.before(:suite) do
    conn = ActiveRecord::Base.connection
    # Партиції-нащадки пропускаємо: `EXISTS` на батьківській таблиці вже накриває їх,
    # а перелічувати 269 дітей означало б платити за той самий факт двічі.
    children = conn.select_values("SELECT inhrelid::regclass::text FROM pg_inherits")
    # `spatial_ref_sys` наповнює саме розширення PostGIS — це довідник, не наші дані.
    scannable = conn.tables - children - %w[spatial_ref_sys ar_internal_metadata schema_migrations]
    probe = scannable.map { |t|
      "SELECT #{conn.quote(t)} AS t WHERE EXISTS (SELECT 1 FROM #{conn.quote_table_name(t)})"
    }.join(" UNION ALL ")

    dirty = probe.empty? ? [] : conn.select_values(probe)
    unless dirty.empty?
      # `raise`, а не `abort`: RSpec рендерить помилку `before(:suite)`-хука ще й
      # унизу звіту, тож причина видима і тому, хто дивиться лише хвіст логу.
      # `abort` лишав у хвості голе «0 examples, 0 failures» — форма, що читається
      # як зелень (`00_07` TEST.9 §діагностичні рефлекси).
      raise <<~MSG
        \n🔴 test-БД НЕ ПОРОЖНЯ на старті сюїти — прогін вимірював би не код, а залишки.
        Непорожні таблиці: #{dirty.sort.join(', ')}

        Найімовірніша причина — `bin/rails runner`/`console` у RAILS_ENV=test: він
        пише повз транзакційні фікстури, тож probe-записи переживають прогін.
        Полагодити: `RAILS_ENV=test bin/rails db:test:prepare`
        Не повторити:  обгортай runner-тіло в `ActiveRecord::Base.transaction { …; raise ActiveRecord::Rollback }`
      MSG
    end
  end

  # Infer spec type from file location (e.g. spec/models → type: :model).
  config.infer_spec_type_from_file_location!

  # Remove Rails internals from backtraces for cleaner failure output.
  config.filter_rails_from_backtrace!

  # Honour :focus tag so that `fit` / `fdescribe` / `fcontext` work here too.
  config.filter_run_when_matching :focus

  # [UI.3, ⚖️ 2026-08-20] Advisory-прогони (axe-lens) — ПОЗА дефолтною сюїтою
  # й CI за присудом: їхні падіння — звіт для тріажу, не вердикт про дерево.
  # Запуск руками: `bin/rspec spec/features/axe_audit_spec.rb --tag advisory`.
  config.filter_run_excluding advisory: true

  # Clear Sidekiq queues before each example so jobs don't bleed between tests.
  # Clear Rails cache so rate-limit counters and silence filters don't leak across examples.
  # Drop Kredis keys (M2M replay nonces, distributed locks) between tests.
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
      redis = Kredis.redis(config: :shared)
      # 🔴 [INF.22] `clear_all`, НЕ `flushdb` — і різниця тут несуча в обидва боки.
      # Доти цей рядок робив `flushdb`, бо Kredis жив у власній DB 1; Upstash дає
      # рівно ОДНУ логічну базу (виміряно 2026-08-30), тож dev/test зведено на неї
      # ж — і `flushdb` тепер вимивав би заразом черги Sidekiq. Із заданим
      # `Kredis.global_namespace` гем видаляє лише `silken:*`.
      Kredis.clear_all
      # 🔴 [TEST.8] Освіжити TTL мітки власника. ⚠️ Підстава цього рядка ЗМІНИЛАСЬ:
      # доти він ВІДНОВЛЮВАВ мітку, бо `flushdb` стирав її разом з усім (ключ,
      # поставлений у `before(:suite)`, не переживав навіть першого прикладу, і
      # вікно детекції стискалось до збігу двох стартів у суб-секунду). Тепер
      # `SUITE_OWNER_KEY` лежить ПОЗА namespace `silken:`, тож зачистка його не
      # чіпає взагалі — лишається єдина робота, продовження TTL на довгому
      # прогоні. `after(:suite)` лишається єдиним, хто мітку знімає.
      redis.set(SUITE_OWNER_KEY, Process.pid, ex: 2.hours.to_i)
    rescue RedisClient::CannotConnectError, Redis::CannotConnectError, RedisClient::ConnectionError, Errno::ECONNREFUSED
      # Redis may not be available in CI — safe to skip flush
    end
  end

  # Reset I18n.locale between examples — the LocalesController#update endpoint
  # mutates I18n.locale globally (Thread-local), so without this reset a single
  # POST /locale spec leaks the locale into every subsequent example
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

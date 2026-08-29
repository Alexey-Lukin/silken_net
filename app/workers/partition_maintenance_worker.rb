# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class PartitionMaintenanceWorker
  include Sidekiq::Job

  # Інфраструктурне обслуговування — стандартний пріоритет, 3 ретраї.
  # DDL-операція ідемпотентна, тому ретраї безпечні.
  sidekiq_options queue: "default", retry: 3

  # Таблиці з декларативним партиціюванням RANGE за created_at.
  # Якщо додаєте нову RANGE-партиційну таблицю — внесіть її сюди І перевірте
  # `spec/workers/partition_maintenance_worker_spec.rb` (очікуване число логів).
  PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs blockchain_transactions].freeze

  def perform
    today = Time.current.utc.to_date
    months = [ today.beginning_of_month, (today + 1.month).beginning_of_month ]
    created = 0  # initialised early so the Sentry rescue payload is always defined

    Rails.logger.info "🗂️ [Partition Maintenance] Перевірка партицій для #{months.map { _1.strftime('%Y-%m') }.join(', ')}..."

    PARTITIONED_TABLES.each do |table_name|
      months.each do |month_start|
        created += ensure_partition(table_name, month_start)
      end
    end

    Rails.logger.info "✅ [Partition Maintenance] Завершено. Створено нових партицій: #{created}"

    sample_growth_gauges!
  rescue StandardError => e
    # CRITICAL: silent partition-creation failure is catastrophic — the very next
    # INSERT against the affected table on day-1 of the new month crashes with
    # `no partition of relation "<table>" found for row`. We re-raise so Sidekiq
    # picks it up for the configured `retry: 3`, increment a Prometheus counter
    # (Grafana P0 alert, 06_03 §2.8 / 00_07 S2.5) AND report to Sentry so the operator
    # gets paged BEFORE the partition window expires.
    SilkenNet::Metrics::PARTITION_MAINTENANCE_FAILURES_TOTAL.increment
    if defined?(Sentry)
      Sentry.capture_exception(
        e,
        tags: { worker: "PartitionMaintenanceWorker", severity: "critical" },
        extra: { tables: PARTITIONED_TABLES, months: months.map(&:to_s), created_so_far: created }
      )
    end
    Rails.logger.error "🛑 [Partition Maintenance CRITICAL] #{e.class}: #{e.message}"
    raise
  end

  private

  # Створює партицію для вказаної таблиці та місяця, якщо її ще не існує.
  # Повертає 1 якщо партицію було створено, 0 якщо вона вже існувала.
  def ensure_partition(table_name, month_start)
    conn = ActiveRecord::Base.connection
    partition_name = partition_name_for(table_name, month_start)
    range_from = month_start.strftime("%Y-%m-%d 00:00:00")
    range_to = (month_start + 1.month).strftime("%Y-%m-%d 00:00:00")

    sql = <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{conn.quote_table_name(partition_name)}
      PARTITION OF #{conn.quote_table_name(table_name)}
      FOR VALUES FROM (#{conn.quote(range_from)}) TO (#{conn.quote(range_to)})
    SQL

    conn.execute(sql)

    Rails.logger.info "🗂️ [Partition Maintenance] Партиція #{partition_name} — OK"
    1
  rescue ActiveRecord::StatementInvalid => e
    if e.message.include?("already exists")
      Rails.logger.info "🗂️ [Partition Maintenance] Партиція #{partition_name} вже існує — пропущено"
      0
    else
      # DEFAULT-блокування розпізнаємо КЛАСОМ причини, не текстом: `CheckViolation`
      # тут може означати лише одне — DEFAULT-лист уже тримає рядок цього місяця,
      # тож нова партиція звузила б його constraint. Ретрай не лікує (стан сам не
      # змінюється), і саме це оператор мусить прочитати в логу, а не виводити з
      # тексту Postgres. Гілку `already exists` вище свідомо не чіпаємо.
      if e.cause.is_a?(PG::CheckViolation)
        Rails.logger.error "🛑 [Partition Maintenance] #{partition_name}: DEFAULT-лист уже тримає рядки цього " \
                           "місяця — створення заблоковано, і РЕТРАЇ ЦЬОГО НЕ ВИПРАВЛЯТЬ. Потрібна ручна дія " \
                           "(DETACH default → перелити рядки → ATTACH). Прилад-попередження: " \
                           "`silkennet_partition_default_occupied`. Рунбук — 06_06 §5.5."
      end
      Rails.logger.error "🛑 [Partition Maintenance] Помилка створення #{partition_name}: #{e.message}"
      raise
    end
  end

  # [ARCH.70] Прилад росту: скільки партицій накопичено і скільки вони важать.
  # Без нього поріг «пора дропати» невидимий, тобто ⚖️ про ширину вікна дропу
  # ухвалюється наосліп.
  #
  # 🔴 Власний `rescue` тут НЕ дублює зовнішній, а свідомо його оминає: той
  # інкрементить `PARTITION_MAINTENANCE_FAILURES_TOTAL` і re-raise'ить, тобто
  # виняток ВИМІРЮВАННЯ підняв би P0-пейдж «партиція наступного місяця може бути
  # відсутня» і Sidekiq-ретрай уже виконаного DDL. Ціна тиші приладу менша за
  # ціну хибного P0 на критичному шляху.
  #
  # `pg_partition_tree` віддає предка + усіх нащадків; предок партиційної таблиці
  # сторінок не має, тож сума по всьому дереву і є розміром таблиці з індексами
  # й TOAST. Агрегат завжди повертає рядок (на порожньому дереві — 0/NULL), тому
  # `select_one` тут не може віддати `nil` через відсутність партицій.
  def sample_growth_gauges!
    conn = ActiveRecord::Base.connection

    PARTITIONED_TABLES.each do |table_name|
      row = conn.select_one(<<~SQL.squish)
        SELECT count(*) FILTER (WHERE t.isleaf) AS leaves,
               COALESCE(sum(pg_total_relation_size(t.relid)), 0) AS bytes,
               max(t.relid::regclass::text)
                 FILTER (WHERE pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT') AS default_rel
        FROM pg_partition_tree(#{conn.quote(table_name)}) t
        JOIN pg_class c ON c.oid = t.relid
      SQL

      SilkenNet::Metrics::PARTITIONS_PRESENT.set(row["leaves"].to_i, labels: { table: table_name })
      SilkenNet::Metrics::PARTITIONED_TABLE_BYTES.set(row["bytes"].to_i, labels: { table: table_name })

      # DEFAULT-лист питаємо ОКРЕМО й через `EXISTS`: будь-який ОДИН рядок уже
      # блокує `CREATE ... PARTITION OF` для свого місяця назавжди, тож кількість
      # рішення не міняє, а `count(*)` над розрослим DEFAULT сканував би саме
      # тоді, коли прилад найпотрібніший. Ім'я беремо з `relpartbound`, а не з
      # конвенції `<table>_default` — конвенція правдива сьогодні й ніде не
      # гейтована.
      occupied = row["default_rel"] &&
                 conn.select_value("SELECT EXISTS (SELECT 1 FROM #{conn.quote_table_name(row['default_rel'])})")
      SilkenNet::Metrics::PARTITION_DEFAULT_OCCUPIED.set(occupied ? 1 : 0, labels: { table: table_name })

      Rails.logger.info "📊 [Partition Growth] #{table_name}: #{row['leaves']} партицій, " \
                        "#{row['bytes']} Б, default #{occupied ? 'НЕПОРОЖНІЙ ⚠️' : 'порожній'}"
    end

    # [ARCH.70] Третій вимір ретеншну — РЯДКИ (місяці й байти вже є вище). Стоїть у
    # ТОМУ САМОМУ проході свідомо: питання одне («що саме зітре майбутнє вікно»), тож
    # окремий воркер додав би розклад без нової відповіді, а спільний штамп свіжості
    # нижче накриває всі три виміри разом.
    # ⛔ Величина НЕ є беклогом — підпис і підстава в шапці метрики; лічба index-only
    # через партіальний індекс, тому дешева навіть на розрослих партиціях.
    SilkenNet::Metrics::TELEMETRY_ORACLE_DISPATCHED_ROWS.set(
      TelemetryLog.where(oracle_status: :dispatched).count
    )

    # Штамп ставиться ЛИШЕ після повного проходу — частковий семпл не є свідком
    # свіжості: якби він оновлював штамп, замерзлий гейдж однієї таблиці виглядав
    # би щойно виміряним.
    SilkenNet::Metrics::PARTITION_SAMPLE_TIMESTAMP.set(Time.current.to_i)
  rescue StandardError => e
    Rails.logger.warn "📊 [Partition Growth] семпл не вдався (прилад, не критичний шлях): #{e.class}: #{e.message}"
  end

  # Генерує ім'я партиції у форматі, що використовується в проєкті:
  # telemetry_logs_y2026m03, gateway_telemetry_logs_y2026m04
  def partition_name_for(table_name, month_start)
    "#{table_name}_y#{month_start.strftime('%Y')}m#{month_start.strftime('%m')}"
  end
end

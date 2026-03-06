# frozen_string_literal: true

# 🛠️ Kenosis Titan: Оптимізація GatewayTelemetryLog для Series C/D масштабу
#
# 1. Партиціювання gateway_telemetry_logs за місяцями (PostgreSQL RANGE partitioning).
#    На масштабі Series C (тисячі шлюзів, пакет кожні 5-10 хв) таблиця накопичить
#    мільярди записів за рік. Без партиціювання order(created_at: :desc) та будь-який
#    пошук по queen_uid «вішають» базу.
# 2. Новий композитний індекс (queen_uid, created_at) для швидкого пошуку по шлюзу.
#    Замінює full-scan при .recent та has_one :latest_gateway_telemetry_log.
class PartitionGatewayTelemetryLogs < ActiveRecord::Migration[8.1]
  def up
    # ──────────────────────────────────────────────────────
    # 1. Видаляємо FK перед перейменуванням (вимога PostgreSQL)
    # ──────────────────────────────────────────────────────
    remove_foreign_key :gateway_telemetry_logs, :gateways

    # ──────────────────────────────────────────────────────
    # 2. Зберігаємо структуру старої таблиці
    # ──────────────────────────────────────────────────────
    rename_table :gateway_telemetry_logs, :gateway_telemetry_logs_legacy

    # ──────────────────────────────────────────────────────
    # 3. Створюємо партиціоновану таблицю
    #    PK = (id, created_at) — вимога PostgreSQL для RANGE partitioning
    # ──────────────────────────────────────────────────────
    execute <<~SQL
      CREATE TABLE gateway_telemetry_logs (
        id bigserial NOT NULL,
        gateway_id bigint NOT NULL,
        queen_uid varchar,
        voltage_mv numeric,
        cellular_signal_csq integer,
        temperature_c numeric,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        PRIMARY KEY (id, created_at)
      ) PARTITION BY RANGE (created_at);
    SQL

    # ──────────────────────────────────────────────────────
    # 4. Індекси (автоматично наслідуються партиціями)
    # ──────────────────────────────────────────────────────

    # Існуючий індекс на gateway_id (FK-lookup)
    execute "CREATE INDEX index_gateway_telemetry_logs_on_gateway_id ON gateway_telemetry_logs (gateway_id)"

    # [НОВИЙ]: Композитний індекс для has_one :latest_gateway_telemetry_log
    # та scope :recent — замінює full-scan при order(created_at: :desc)
    execute "CREATE INDEX idx_gateway_telemetry_logs_queen_uid_created ON gateway_telemetry_logs (queen_uid, created_at)"

    # ──────────────────────────────────────────────────────
    # 5. Foreign Key (підтримується з PostgreSQL 12+)
    # ──────────────────────────────────────────────────────
    execute "ALTER TABLE gateway_telemetry_logs ADD CONSTRAINT fk_gateway_telemetry_logs_gateway_id FOREIGN KEY (gateway_id) REFERENCES gateways(id)"

    # ──────────────────────────────────────────────────────
    # 6. Партиції: поточний квартал + запас
    # ──────────────────────────────────────────────────────
    execute "CREATE TABLE gateway_telemetry_logs_y2026m01 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-01-01') TO ('2026-02-01')"
    execute "CREATE TABLE gateway_telemetry_logs_y2026m02 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-02-01') TO ('2026-03-01')"
    execute "CREATE TABLE gateway_telemetry_logs_y2026m03 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-03-01') TO ('2026-04-01')"
    execute "CREATE TABLE gateway_telemetry_logs_y2026m04 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-04-01') TO ('2026-05-01')"
    execute "CREATE TABLE gateway_telemetry_logs_y2026m05 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-05-01') TO ('2026-06-01')"
    execute "CREATE TABLE gateway_telemetry_logs_y2026m06 PARTITION OF gateway_telemetry_logs FOR VALUES FROM ('2026-06-01') TO ('2026-07-01')"

    # Default-партиція для даних поза визначеними діапазонами
    execute "CREATE TABLE gateway_telemetry_logs_default PARTITION OF gateway_telemetry_logs DEFAULT"

    # ──────────────────────────────────────────────────────
    # 7. Міграція існуючих даних та видалення legacy
    #    Явний перелік колонок запобігає помилкам через різний порядок стовпців
    # ──────────────────────────────────────────────────────
    execute <<~SQL
      INSERT INTO gateway_telemetry_logs (
        id, gateway_id, queen_uid, voltage_mv, cellular_signal_csq,
        temperature_c, created_at, updated_at
      )
      SELECT
        id, gateway_id, queen_uid, voltage_mv, cellular_signal_csq,
        temperature_c, created_at, updated_at
      FROM gateway_telemetry_logs_legacy
    SQL
    drop_table :gateway_telemetry_logs_legacy
  end

  def down
    # ──────────────────────────────────────────────────────
    # Відкат: відтворюємо звичайну таблицю
    # ──────────────────────────────────────────────────────
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_default"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m06"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m05"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m04"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m03"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m02"
    execute "ALTER TABLE gateway_telemetry_logs DETACH PARTITION gateway_telemetry_logs_y2026m01"

    rename_table :gateway_telemetry_logs, :gateway_telemetry_logs_partitioned

    create_table :gateway_telemetry_logs do |t|
      t.bigint :gateway_id, null: false
      t.string :queen_uid
      t.decimal :voltage_mv
      t.integer :cellular_signal_csq
      t.decimal :temperature_c
      t.timestamps
    end

    add_index :gateway_telemetry_logs, :gateway_id,
              name: "index_gateway_telemetry_logs_on_gateway_id"
    add_foreign_key :gateway_telemetry_logs, :gateways,
                    name: "fk_rails_1df16206a5", column: :gateway_id

    execute <<~SQL
      INSERT INTO gateway_telemetry_logs (
        id, gateway_id, queen_uid, voltage_mv, cellular_signal_csq,
        temperature_c, created_at, updated_at
      )
      SELECT
        id, gateway_id, queen_uid, voltage_mv, cellular_signal_csq,
        temperature_c, created_at, updated_at
      FROM gateway_telemetry_logs_partitioned
    SQL

    execute "DROP TABLE gateway_telemetry_logs_default"
    execute "DROP TABLE gateway_telemetry_logs_y2026m06"
    execute "DROP TABLE gateway_telemetry_logs_y2026m05"
    execute "DROP TABLE gateway_telemetry_logs_y2026m04"
    execute "DROP TABLE gateway_telemetry_logs_y2026m03"
    execute "DROP TABLE gateway_telemetry_logs_y2026m02"
    execute "DROP TABLE gateway_telemetry_logs_y2026m01"
    execute "DROP TABLE gateway_telemetry_logs_partitioned"
  end
end

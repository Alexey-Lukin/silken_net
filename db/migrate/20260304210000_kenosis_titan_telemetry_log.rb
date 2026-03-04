# frozen_string_literal: true

# 🛠️ Kenosis Titan: Оптимізація TelemetryLog для Series C/D масштабу
#
# 1. health_streak — денормалізований лічильник здорових пакетів поспіль (Anti-Flapping).
#    Замінює N+1 запит у recovery_confirmed?.
# 2. Композитні індекси для швидкої аналітики anomalies та seismic_activity скоупів.
# 3. Партиціювання telemetry_logs за місяцями (PostgreSQL RANGE partitioning).
class KenosisTitanTelemetryLog < ActiveRecord::Migration[8.1]
  def up
    # ──────────────────────────────────────────────────────
    # 1. Денормалізований лічильник здоров'я на Tree
    # ──────────────────────────────────────────────────────
    add_column :trees, :health_streak, :integer, default: 0, null: false

    # ──────────────────────────────────────────────────────
    # 2. Зберігаємо структуру старої таблиці, видаляємо FK
    # ──────────────────────────────────────────────────────
    remove_foreign_key :telemetry_logs, :trees
    rename_table :telemetry_logs, :telemetry_logs_legacy

    # ──────────────────────────────────────────────────────
    # 3. Створюємо партиціоновану таблицю
    #    PK = (id, created_at) — вимога PostgreSQL для RANGE partitioning
    # ──────────────────────────────────────────────────────
    execute <<~SQL
      CREATE TABLE telemetry_logs (
        id bigserial NOT NULL,
        acoustic_events integer,
        bio_status integer,
        created_at timestamp(6) NOT NULL,
        firmware_version_id bigint,
        growth_points numeric,
        mesh_ttl integer,
        metabolism_s integer,
        piezo_voltage_mv integer,
        queen_uid varchar,
        rssi integer,
        tamper_detected boolean,
        temperature_c numeric,
        tree_id bigint NOT NULL,
        updated_at timestamp(6) NOT NULL,
        voltage_mv integer,
        z_value numeric,
        PRIMARY KEY (id, created_at)
      ) PARTITION BY RANGE (created_at);
    SQL

    # ──────────────────────────────────────────────────────
    # 4. Індекси (автоматично наслідуються партиціями)
    # ──────────────────────────────────────────────────────

    # Існуючі індекси (відтворення)
    execute "CREATE INDEX index_telemetry_logs_on_tree_id ON telemetry_logs (tree_id)"
    execute "CREATE INDEX index_telemetry_logs_on_tree_id_and_created_at ON telemetry_logs (tree_id, created_at)"

    # Нові композитні індекси для аналітики Оракула (AiInsight)
    execute "CREATE INDEX idx_telemetry_logs_bio_status_created ON telemetry_logs (bio_status, created_at)"
    execute "CREATE INDEX idx_telemetry_logs_piezo_created ON telemetry_logs (piezo_voltage_mv, created_at)"

    # ──────────────────────────────────────────────────────
    # 5. Foreign Key
    # ──────────────────────────────────────────────────────
    execute "ALTER TABLE telemetry_logs ADD CONSTRAINT fk_telemetry_logs_tree_id FOREIGN KEY (tree_id) REFERENCES trees(id)"

    # ──────────────────────────────────────────────────────
    # 6. Партиції: поточний квартал + запас
    # ──────────────────────────────────────────────────────
    execute "CREATE TABLE telemetry_logs_y2026m01 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-01-01') TO ('2026-02-01')"
    execute "CREATE TABLE telemetry_logs_y2026m02 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-02-01') TO ('2026-03-01')"
    execute "CREATE TABLE telemetry_logs_y2026m03 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-03-01') TO ('2026-04-01')"
    execute "CREATE TABLE telemetry_logs_y2026m04 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-04-01') TO ('2026-05-01')"
    execute "CREATE TABLE telemetry_logs_y2026m05 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-05-01') TO ('2026-06-01')"
    execute "CREATE TABLE telemetry_logs_y2026m06 PARTITION OF telemetry_logs FOR VALUES FROM ('2026-06-01') TO ('2026-07-01')"

    # Default-партиція для даних поза визначеними діапазонами
    execute "CREATE TABLE telemetry_logs_default PARTITION OF telemetry_logs DEFAULT"

    # ──────────────────────────────────────────────────────
    # 7. Міграція існуючих даних та видалення legacy
    #    Явний перелік колонок запобігає помилкам через різний порядок стовпців
    # ──────────────────────────────────────────────────────
    execute <<~SQL
      INSERT INTO telemetry_logs (
        id, acoustic_events, bio_status, created_at, firmware_version_id,
        growth_points, mesh_ttl, metabolism_s, piezo_voltage_mv, queen_uid,
        rssi, tamper_detected, temperature_c, tree_id, updated_at, voltage_mv, z_value
      )
      SELECT
        id, acoustic_events, bio_status, created_at, firmware_version_id,
        growth_points, mesh_ttl, metabolism_s, piezo_voltage_mv, queen_uid,
        rssi, tamper_detected, temperature_c, tree_id, updated_at, voltage_mv, z_value
      FROM telemetry_logs_legacy
    SQL
    drop_table :telemetry_logs_legacy
  end

  def down
    # ──────────────────────────────────────────────────────
    # Відкат: відтворюємо звичайну таблицю
    # ──────────────────────────────────────────────────────
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_default"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m06"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m05"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m04"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m03"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m02"
    execute "ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_y2026m01"

    rename_table :telemetry_logs, :telemetry_logs_partitioned

    create_table :telemetry_logs do |t|
      t.integer :acoustic_events
      t.integer :bio_status
      t.bigint :firmware_version_id
      t.decimal :growth_points
      t.integer :mesh_ttl
      t.integer :metabolism_s
      t.integer :piezo_voltage_mv
      t.string :queen_uid
      t.integer :rssi
      t.boolean :tamper_detected
      t.decimal :temperature_c
      t.bigint :tree_id, null: false
      t.integer :voltage_mv
      t.decimal :z_value
      t.timestamps
    end

    add_index :telemetry_logs, :tree_id
    add_index :telemetry_logs, [ :tree_id, :created_at ]
    add_foreign_key :telemetry_logs, :trees

    execute <<~SQL
      INSERT INTO telemetry_logs (
        id, acoustic_events, bio_status, created_at, firmware_version_id,
        growth_points, mesh_ttl, metabolism_s, piezo_voltage_mv, queen_uid,
        rssi, tamper_detected, temperature_c, tree_id, updated_at, voltage_mv, z_value
      )
      SELECT
        id, acoustic_events, bio_status, created_at, firmware_version_id,
        growth_points, mesh_ttl, metabolism_s, piezo_voltage_mv, queen_uid,
        rssi, tamper_detected, temperature_c, tree_id, updated_at, voltage_mv, z_value
      FROM telemetry_logs_partitioned
    SQL

    execute "DROP TABLE telemetry_logs_default"
    execute "DROP TABLE telemetry_logs_y2026m06"
    execute "DROP TABLE telemetry_logs_y2026m05"
    execute "DROP TABLE telemetry_logs_y2026m04"
    execute "DROP TABLE telemetry_logs_y2026m03"
    execute "DROP TABLE telemetry_logs_y2026m02"
    execute "DROP TABLE telemetry_logs_y2026m01"
    execute "DROP TABLE telemetry_logs_partitioned"

    remove_column :trees, :health_streak
  end
end

# frozen_string_literal: true

class FinalizeSilkenNetArchitecture < ActiveRecord::Migration[8.1]
  def change
    # --- 1. ПЕРЕХІД НА RAILS 8 СТАНДАРТ ---
    rename_column :users, :email, :email_address
    add_column :users, :phone_number, :string
    add_column :users, :last_seen_at, :datetime
    add_index :users, :last_seen_at

    # --- 2. ZERO-TRUST SECURITY (HardwareKey) ---
    # Відв'язуємо ключ від конкретного дерева, робимо його універсальним для пристроїв (did/uid)
    remove_reference :hardware_keys, :tree, foreign_key: true
    add_column :hardware_keys, :device_uid, :string
    rename_column :hardware_keys, :aes_key, :aes_key_hex
    add_index :hardware_keys, :device_uid, unique: true

    # --- 3. TELEMETRY LOGS (Синхронізація з UnpackerService) ---
    add_column :telemetry_logs, :rssi, :integer
    # Переконуємось, що назви полів збігаються з воркерами
    # piezo_voltage_mv already correct — no rename needed
    add_index :telemetry_logs, [ :tree_id, :created_at ]
    add_index :telemetry_logs, :status_code if column_exists?(:telemetry_logs, :status_code)

    # --- 4. AI INSIGHTS (Перехід на Поліморфізм та Прогнози) ---
    # Тепер інсайт може належати як Дереву, так і Кластеру
    remove_reference :ai_insights, :cluster, foreign_key: true
    add_reference :ai_insights, :analyzable, polymorphic: true, index: true

    # Додаємо поля для добової аналітики та прогнозів
    add_column :ai_insights, :analyzed_date, :date
    add_column :ai_insights, :average_temperature, :decimal
    add_column :ai_insights, :stress_index, :decimal
    add_column :ai_insights, :total_growth_points, :integer
    add_column :ai_insights, :summary, :text
    add_column :ai_insights, :probability_score, :decimal
    add_column :ai_insights, :target_date, :date
    add_column :ai_insights, :reasoning, :jsonb

    # --- 5. EWS ALERTS (Журнал порятунку) ---
    add_column :ews_alerts, :resolved_at, :datetime
    add_index :ews_alerts, :resolved_at

    # --- 6. DEVICE CALIBRATION (Лінза істини) ---
    rename_column :device_calibrations, :temp_offset, :temperature_offset_c
    rename_column :device_calibrations, :acoustic_offset, :impedance_offset_ohms
    add_column :device_calibrations, :vcap_coefficient, :decimal, default: 1.0

    # --- 7. ACTUATORS (Виконавчі механізми) ---
    add_column :actuators, :last_activated_at, :datetime

    # --- 8. CLUSTERS (Картографія) ---
    add_column :clusters, :geojson_polygon, :jsonb
    add_column :clusters, :climate_type, :string

    # --- 9. TREES (Статус життя) ---
    add_column :trees, :status, :integer, default: 0
    add_index :trees, :status
  end
end

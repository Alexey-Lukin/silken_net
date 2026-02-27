# frozen_string_literal: true

class TelemetryLog < ApplicationRecord
  belongs_to :tree
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid, optional: true
  # Зв'язок для трекінгу OTA-оновлень (з 4 байтів padding-у)
  belongs_to :bio_contract_firmware, foreign_key: :firmware_version_id, optional: true

  enum :bio_status, {
    homeostasis: 0, # Здоровий Хаос
    stress: 1,      # Сигнал раннього попередження (Посуха)
    anomaly: 2      # Критичний стрес / Пилка
  }, prefix: true

  # [ДОДАТКОВО]: Додаємо z_value для Атрактора Лоренца
  # Це поле ми заклали в схему для математичної валідації гомеостазу.
  validates :z_value, numericality: true, allow_nil: true

  # Додано mesh_ttl (з 12-го байта payload) для картування естафети пакетів
  validates :voltage_mv, :temperature_c, :acoustic_events, :metabolism_s, :growth_points, :mesh_ttl, presence: true
  
  # Валідація п'єзо-напруги (Сейсмічний Метаматеріал)
  validates :piezo_voltage_mv, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :anomalies, -> { where(bio_status: [ :stress, :anomaly ]).or(where("acoustic_events > ?", 0)) }
  scope :in_timeframe, ->(start_time, end_time) { where(created_at: start_time..end_time) }
  
  # Шукаємо пакети, де апаратно зафіксовано відкриття титанового корпусу (вандалізм)
  scope :vandalized, -> { where(tamper_detected: true) }
  
  # Шукаємо аномальні стрибки п'єзо-резонансу (потенційний передвісник землетрусу)
  scope :seismic_activity, -> { where("piezo_voltage_mv > ?", 1500) }

  # Аналітика топології: перевірка, чи пакет дійшов безпосередньо, чи через інші дерева
  def relayed_via_mesh?(initial_ttl = 5)
    mesh_ttl < initial_ttl
  end
end

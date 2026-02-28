# frozen_string_literal: true

class TelemetryLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  belongs_to :tree
  # Зв'язок із Королевою через її UID
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid, optional: true
  # Трекінг версії прошивки (з 4 байтів padding-у)
  belongs_to :bio_contract_firmware, foreign_key: :firmware_version_id, optional: true

  # --- СТАТУСИ (The Pulse of Life) ---
  # [СИНХРОНІЗОВАНО]: Додано tamper_detected для відповідності сервісам
  enum :bio_status, {
    homeostasis: 0,      # Здоровий Хаос (Атрактор у нормі)
    stress: 1,           # Раннє попередження (Посуха)
    anomaly: 2,          # Критичний збій / Хвороба
    tamper_detected: 3   # Вандалізм / Розкриття корпусу
  }, prefix: true

  # --- ВАЛІДАЦІЇ (The Truth Constraints) ---
  # z_value - результат розрахунку Атрактора Лоренца
  validates :z_value, numericality: true, allow_nil: true
  
  # Базові метрики від Солдата
  validates :voltage_mv, :temperature_c, :acoustic_events, :metabolism_s, :growth_points, :mesh_ttl, presence: true
  
  # Сейсмічний Метаматеріал (П'єзо-резонанс)
  validates :piezo_voltage_mv, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # --- СКОУПИ (The Analytical Eyes) ---
  scope :recent, -> { order(created_at: :desc) }
  
  # Аномалії включають стрес, критику та акустичні сплески
  scope :anomalies, -> { 
    where(bio_status: [:stress, :anomaly, :tamper_detected])
    .or(where("acoustic_events > ?", 50)) 
  }
  
  scope :in_timeframe, ->(start_time, end_time) { where(created_at: start_time..end_time) }
  
  # [ВИПРАВЛЕНО]: Використовуємо енум замість окремої колонки
  scope :vandalized, -> { bio_status_tamper_detected }
  
  # Моніторинг сейсмічної активності через п'єзо-датчик
  scope :seismic_activity, -> { where("piezo_voltage_mv > ?", 1500) }

  # --- МЕТОДИ (Topology Analysis) ---
  
  # Перевірка, чи пакет пройшов через Mesh-мережу інших дерев
  def relayed_via_mesh?(initial_ttl = 5)
    mesh_ttl < initial_ttl
  end

  # Швидка перевірка на критичність для UI
  def critical?
    bio_status_anomaly? || bio_status_tamper_detected?
  end
end

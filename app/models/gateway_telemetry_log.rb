# frozen_string_literal: true

class GatewayTelemetryLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid

  # --- ВАЛІДАЦІЇ ---
  # voltage_mv: Напруга батареї/сонячної панелі Шлюзу
  # temperature_c: Внутрішня температура корпусу
  # cellular_signal_csq: Якість зв'язку SIM7070G (0-31, 99 - unknown)
  validates :voltage_mv, :temperature_c, :cellular_signal_csq, :queen_uid, presence: true
  
  # CSQ 0-31 — це нормальний діапазон, 99 — сигнал відсутній/невизначений
  validates :cellular_signal_csq, inclusion: { in: 0..31.union([99]) }

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :critical_battery, -> { where("voltage_mv < ?", 3300) }
  # SIM7070G починає деградувати при температурі понад 65°C
  scope :overheated, -> { where("temperature_c > ?", 65) }

  # --- МЕТОДИ (Health Intelligence) ---

  # Допоміжний метод для дашборду (переведення CSQ у відсотки)
  def signal_quality_percentage
    return 0 if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    ((cellular_signal_csq / 31.0) * 100.0).round(1)
  end

  # [НОВЕ]: Перерахунок CSQ у dBm (стандарт 3GPP)
  # Формула: RSSI (dBm) = 2 * CSQ - 113
  # Результат від -113 dBm (жахливо) до -51 dBm (ідеально)
  def signal_dbm
    return nil if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    (2 * cellular_signal_csq) - 113
  end

  # [НОВЕ]: Швидка перевірка на критичний стан заліза
  def critical_fault?
    voltage_mv < 3300 || temperature_c > 65
  end
end

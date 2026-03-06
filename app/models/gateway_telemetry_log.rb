# frozen_string_literal: true

class GatewayTelemetryLog < ApplicationRecord
  # --- КОНСТАНТИ ПОРОГІВ (Single Source of Truth) ---
  LOW_BATTERY_THRESHOLD = 3300  # mV: нижче цього — виснаження батареї/сонячної панелі
  OVERHEAT_THRESHOLD    = 65    # °C: SIM7070G починає деградувати при перевищенні
  LOW_SIGNAL_THRESHOLD  = 5     # CSQ: нижче 5 — ризик втрати батчів телеметрії

  # --- ЗВ'ЯЗКИ ---
  # Зв'язок через UID дозволяє зберігати логіку ідентифікації заліза
  # навіть якщо записи в базі будуть перенесені або архівуватися.
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid

  # --- ВАЛІДАЦІЇ ---
  # [KENOSIS TITAN]: Валідації видалено з hot path.
  # На Series C/D масштабі (тисячі шлюзів, пакет кожні 5-10 хв) дані перевіряються
  # в GatewayTelemetryWorker.valid_gateway_stats? до створення запису.
  # ActiveRecord валідації на кожному INSERT (зокрема при insert_all) — зайві цикли CPU.

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :critical_battery, -> { where("voltage_mv < ?", LOW_BATTERY_THRESHOLD) }
  scope :overheated, -> { where("temperature_c > ?", OVERHEAT_THRESHOLD) }
  scope :weak_signal, -> { where("cellular_signal_csq < ? AND cellular_signal_csq != 99", LOW_SIGNAL_THRESHOLD) }

  # --- МЕТОДИ (Health Intelligence) ---

  # Допоміжний метод для дашборду (переведення CSQ у відсотки)
  def signal_quality_percentage
    return 0 if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    ((cellular_signal_csq / 31.0) * 100.0).round(1)
  end

  # [НОВЕ]: Перерахунок CSQ у dBm (стандарт 3GPP)
  # Формула: RSSI (dBm) = 2 * CSQ - 113
  # Результат від -113 dBm (гранична чутливість) до -51 dBm (ідеальний сигнал)
  def signal_dbm
    return nil if cellular_signal_csq == 99 || cellular_signal_csq.nil?
    (2 * cellular_signal_csq) - 113
  end

  # [НОВЕ]: Швидка перевірка на критичний стан заліза
  # Використовується GatewayTelemetryWorker для ініціації EwsAlert.
  # Nil-safe: без AR-валідацій поля можуть бути nil при direct insert_all.
  def critical_fault?
    return false if voltage_mv.nil? || temperature_c.nil? || cellular_signal_csq.nil?

    voltage_mv < LOW_BATTERY_THRESHOLD ||
      temperature_c > OVERHEAT_THRESHOLD ||
      (cellular_signal_csq != 99 && cellular_signal_csq < LOW_SIGNAL_THRESHOLD)
  end
end

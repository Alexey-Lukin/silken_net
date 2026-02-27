# frozen_string_literal: true

class GatewayTelemetryLog < ApplicationRecord
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid

  # voltage_mv: Напруга батареї/сонячної панелі Шлюзу
  # temperature_c: Внутрішня температура корпусу
  # cellular_signal_csq: Якість зв'язку SIM7070G (0-31)
  validates :voltage_mv, :temperature_c, :cellular_signal_csq, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :critical_battery, -> { where("voltage_mv < ?", 3300) }

  # Допоміжний метод для дашборду (переведення CSQ у відсотки)
  def signal_quality_percentage
    return 0 if cellular_signal_csq == 99 
    (cellular_signal_csq / 31.0) * 100.0
  end
end

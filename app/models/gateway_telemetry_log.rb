# frozen_string_literal: true

class GatewayTelemetryLog < ApplicationRecord
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid

  # voltage_mv: Напруга батареї/сонячної панелі Шлюзу
  # temperature_c: Внутрішня температура корпусу (щоб не перегрівся модем)
  # cellular_signal_csq: Якість зв'язку SIM7070G (від 0 до 31, де 31 - ідеально)
  validates :voltage_mv, :temperature_c, :cellular_signal_csq, presence: true

  scope :recent, -> { order(created_at: :desc) }
  # Скоуп для виявлення Королев, які ризикують "впасти"
  scope :critical_battery, -> { where("voltage_mv < ?", 3300) } # Наприклад, падіння нижче 3.3V

  # Допоміжний метод для дашборду (переведення CSQ у відсотки або dBm)
  def signal_quality_percentage
    return 0 if cellular_signal_csq == 99 # 99 у стандарті AT-команд означає "немає сигналу"
    (cellular_signal_csq / 31.0) * 100.0
  end
end

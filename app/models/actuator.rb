# frozen_string_literal: true

class Actuator < ApplicationRecord
  belongs_to :gateway

  # Типи виконавчих механізмів
  enum :device_type, {
    water_valve: 0,     # Електромагнітний клапан для поливу (Посуха / Пожежа)
    fire_siren: 1,      # Звукова сирена (Пожежа / Вандали)
    seismic_beacon: 2,  # Світлозвуковий маяк евакуації (Землетрус)
    drone_launcher: 3   # Док-станція дрона-розвідника
  }, prefix: true

  # Поточний стан механізму
  enum :state, { idle: 0, active: 1, offline: 2, maintenance_needed: 3 }

  validates :name, :device_type, presence: true

  # Метод-хелпер для перевірки, чи пристрій готовий до роботи
  def ready_for_deployment?
    state_idle? && gateway.last_seen_at > 1.hour.ago
  end
end

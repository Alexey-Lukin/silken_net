# frozen_string_literal: true

class DeviceCalibration < ApplicationRecord
  belongs_to :tree

  # temperature_offset_c: похибка термістора в градусах (напр., -0.5)
  # impedance_offset_ohms: похибка вимірювання опору (напр., +15.0)
  # vcap_coefficient: множник для коригування напруги іоністора (зазвичай 1.0)

  validates :temperature_offset_c, :impedance_offset_ohms, :vcap_coefficient, presence: true, numericality: true

  # Метод для нормалізації сирих даних, що приходять від розпакувальника
  def normalize_temperature(raw_temp)
    raw_temp + temperature_offset_c
  end

  def normalize_impedance(raw_impedance)
    raw_impedance + impedance_offset_ohms
  end
end

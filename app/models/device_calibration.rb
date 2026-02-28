# frozen_string_literal: true

class DeviceCalibration < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :tree

  # --- ВАЛІДАЦІЇ ---
  # temperature_offset_c: похибка в градусах (доданок)
  # impedance_offset_ohms: похибка опору (доданок)
  validates :temperature_offset_c, :impedance_offset_ohms, presence: true, numericality: true
  
  # vcap_coefficient: множник. Він не може бути <= 0.
  validates :vcap_coefficient, presence: true, numericality: { greater_than: 0 }

  # =========================================================================
  # НОРМАЛІЗАЦІЯ СИГНАЛУ (The Signal Purifier)
  # =========================================================================

  def normalize_temperature(raw_temp_c)
    (raw_temp_c + temperature_offset_c).round(2)
  end

  def normalize_impedance(raw_impedance_ohms)
    raw_impedance_ohms + impedance_offset_ohms
  end

  # [НОВЕ]: Додана симетрія. У TelemetryUnpackerService ми робили множення вручну,
  # краще інкапсулювати це тут.
  def normalize_voltage(raw_vcap_mv)
    (raw_vcap_mv * vcap_coefficient).to_i
  end

  # =========================================================================
  # АПАРАТНИЙ АУДИТ (Hardware Decay)
  # =========================================================================

  # Перевірка на фізичну смерть сенсора.
  # Якщо термістор бреше більше ніж на 5 градусів, а опір зсунуто на 500 Ом —
  # калібрування не врятує, потрібен MaintenanceRecord.
  def sensor_drift_critical?
    temperature_offset_c.abs > 5.0 || 
    impedance_offset_ohms.abs > 500.0 || 
    (vcap_coefficient - 1.0).abs > 0.2
  end
end

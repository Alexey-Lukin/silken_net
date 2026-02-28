# frozen_string_literal: true

class DeviceCalibration < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :tree

  # --- КОНСТАНТИ КРИТИЧНОГО ЗСУВУ (Hardware Decay Thresholds) ---
  MAX_TEMP_DRIFT = 5.0
  MAX_IMPEDANCE_DRIFT = 500.0
  MAX_VCAP_TOLERANCE = 0.2 # 20% відхилення від еталону

  # --- ВАЛІДАЦІЇ ---
  validates :temperature_offset_c, :impedance_offset_ohms, presence: true, numericality: true
  validates :vcap_coefficient, presence: true, numericality: { greater_than: 0 }

  # --- ДЕФОЛТНІ ЗНАЧЕННЯ (The Clean Start) ---
  after_initialize :set_defaults, if: :new_record?

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
  # Якщо калібрування виходить за межі розумного — потрібен ремонт (MaintenanceRecord).
  def sensor_drift_critical?
    temperature_offset_c.abs > MAX_TEMP_DRIFT || 
    impedance_offset_ohms.abs > MAX_IMPEDANCE_DRIFT || 
    (vcap_coefficient - 1.0).abs > MAX_VCAP_TOLERANCE
  end

  private

  def set_defaults
    self.temperature_offset_c ||= 0.0
    self.impedance_offset_ohms ||= 0.0
    self.vcap_coefficient ||= 1.0
  end
end

# frozen_string_literal: true

class DeviceCalibration < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :tree

  # --- ДЕЛЕГУВАННЯ ---
  # [N+1 Kill]: Прямий доступ до cluster_id через tree без завантаження Cluster
  delegate :cluster_id, to: :tree

  # --- КОНСТАНТИ КРИТИЧНОГО ЗСУВУ (Hardware Decay Thresholds) ---
  # Межі, за якими програмна корекція стає неможливою
  MAX_TEMP_DRIFT = 5.0
  MAX_IMPEDANCE_DRIFT = 500.0
  MAX_VCAP_TOLERANCE = 0.2 # 20% відхилення

  # --- ВАЛІДАЦІЇ ---
  validates :temperature_offset_c, :impedance_offset_ohms,
            presence: true, numericality: true
  validates :vcap_coefficient,
            presence: true, numericality: { greater_than: 0, less_than: 2.0 }

  # --- КОЛБЕКИ ---
  after_initialize :set_defaults, if: :new_record?
  after_save :check_for_hardware_fault, if: :saved_changes?

  # --- СКОУПИ ---
  scope :critical_drift, -> {
    where("ABS(temperature_offset_c) > ? OR ABS(impedance_offset_ohms) > ?",
          MAX_TEMP_DRIFT, MAX_IMPEDANCE_DRIFT)
  }

  # =========================================================================
  # НОРМАЛІЗАЦІЯ СИГНАЛУ (The Signal Purifier)
  # =========================================================================

  def normalize_temperature(raw_temp_c)
    (raw_temp_c + temperature_offset_c).round(2)
  end

  def normalize_impedance(raw_impedance_ohms)
    (raw_impedance_ohms + impedance_offset_ohms).to_i
  end

  def normalize_voltage(raw_vcap_mv)
    # Коефіцієнт компенсує падіння ємності іоністора або старіння ADC
    (raw_vcap_mv * vcap_coefficient).to_i
  end

  # =========================================================================
  # АПАРАТНИЙ АУДИТ (Hardware Decay)
  # =========================================================================

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

  def check_for_hardware_fault
    return unless sensor_drift_critical?
    return unless tree.cluster_id # [N+1 Kill]: Читаємо FK напряму, без завантаження Cluster

    # [Deduplication Fix]: Шукаємо за tree + alert_type + severity (стабільні ключі),
    # а не за динамічним message, щоб уникнути дублів при повторних save.
    EwsAlert.find_or_create_by!(
      tree: tree,
      alert_type: :system_fault,
      severity: :medium
    ) do |alert|
      alert.cluster_id = tree.cluster_id
      alert.message = "Hardware Decay: Вузол #{tree.did} вимагає заміни."
    end
  end
end

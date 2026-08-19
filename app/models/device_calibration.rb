# SPDX-License-Identifier: AGPL-3.0-or-later
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
  MAX_VCAP_TOLERANCE = 0.2 # 20% відхилення

  # --- ВАЛІДАЦІЇ ---
  validates :temperature_offset_c, presence: true, numericality: true
  validates :vcap_coefficient,
            presence: true, numericality: { greater_than: 0, less_than: 2.0 }

  # --- КОЛБЕКИ ---
  after_initialize :set_defaults, if: :new_record?
  after_save :check_for_hardware_fault, if: :saved_changes?

  # --- СКОУПИ ---
  scope :critical_drift, -> { where("ABS(temperature_offset_c) > ?", MAX_TEMP_DRIFT) }

  # =========================================================================
  # НОРМАЛІЗАЦІЯ СИГНАЛУ (The Signal Purifier)
  # =========================================================================

  # [FW.57 F2] Display/physical calibration ONLY — `temperature_c` feeds the UI,
  # fire-threshold and analytics. It is NOT the Lorenz/DCI temperature: server-side
  # Z + anomaly_ceiling use the device's RAW wire temp (what firmware packed Z
  # from), else a non-zero offset would chaotically diverge server_z from device_z
  # and false-flag fraud. See TelemetryUnpackerService#lorenz_temperature.
  def normalize_temperature(raw_temp_c)
    (raw_temp_c + temperature_offset_c).round(2)
  end

  # [ARCH.99] Вхід — мВ VDDA (шина живлення MCU, VREFINT-калібрування, `03_01` FW.50),
  # а НЕ заряд іоністора: каналу Vcap на вузлі не існує. Коефіцієнт тому компенсує
  # похибку самого тракту вимірювання (розкид VREFINT-калібровки, старіння ADC),
  # а не деградацію ємності — ім'я `vcap_coefficient` історичне.
  def normalize_voltage(raw_vcap_mv)
    (raw_vcap_mv * vcap_coefficient).to_i
  end

  # =========================================================================
  # АПАРАТНИЙ АУДИТ (Hardware Decay)
  # =========================================================================

  # [ARCH.84] ⛔ Обидві диз'юнкти сьогодні структурно ХИБНІ: писачів у жодну з двох
  # колонок немає (ні контролера, ні маршруту, ні сідів), тож рядок живе з дефолтами
  # `1.0`/`0.0` і предикат не істинний НІКОЛИ — `check_for_hardware_fault` озброєний,
  # але не має чим вистрелити. Пускач оживлення — перший писач цих колонок (стендова
  # калібровка). Не «лагодити» предикат і не робити колонки nullable до того: шляху
  # це не будить, лише міняє форму мовчання. Дім присуду — `04_01` картка
  # DeviceCalibration.
  def sensor_drift_critical?
    temperature_offset_c.abs > MAX_TEMP_DRIFT ||
    (vcap_coefficient - 1.0).abs > MAX_VCAP_TOLERANCE
  end

  private

  def set_defaults
    self.temperature_offset_c ||= 0.0
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
      alert.message_key = "hardware_decay"
      alert.message_params = { did: tree.did }
    end
  end
end

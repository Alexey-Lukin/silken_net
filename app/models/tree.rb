# frozen_string_literal: true

class Tree < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model, optional: true
  belongs_to :tree_family

  has_one :wallet, dependent: :destroy

  # Zero-Trust: DID дерева є ключем до його апаратного шифру
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :did, dependent: :destroy

  has_one :device_calibration, dependent: :destroy
  has_many :telemetry_logs, dependent: :destroy
  has_many :ews_alerts, dependent: :destroy
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- ДЕЛЕГУВАННЯ ---
  delegate :name, :attractor_thresholds, to: :tree_family, prefix: true

  # --- СТАН (The Lifecycle) ---
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  # --- ВАЛІДАЦІЇ ---
  before_validation :normalize_did
  validates :did, presence: true, uniqueness: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  # --- КОЛБЕКИ ---
  after_create :build_default_wallet
  after_create :ensure_calibration

  # --- СКОУПИ (The Watchers) ---
  scope :active, -> { where(status: :active) }
  scope :geolocated, -> { where.not(latitude: nil, longitude: nil) }

  # [ОПТИМІЗАЦІЯ]: Використовуємо окрему колонку для швидкодії
  scope :silent, -> { where("last_seen_at < ?", 24.hours.ago) }
  scope :critical_stress, -> {
    joins(:ai_insights)
      .where(ai_insights: { insight_type: :daily_health_summary, target_date: Date.yesterday })
      .where("ai_insights.stress_index > 0.8")
  }

  # --- МЕТОДИ (Intelligence) ---

  # Оновлення пульсу (викликається при розпаковці телеметрії)
  def mark_seen!
    touch(:last_seen_at)
  end

  # Останній вердикт Оракула
  def current_stress
    ai_insights.daily_health_summary.for_date(Date.yesterday).first&.stress_index || 0.0
  end

  def under_threat?
    ews_alerts.unresolved.exists?
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # IONIC INTELLIGENCE (Streaming Potential Management)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Повертає останній зафіксований вольтаж іоністора
  def ionic_voltage
    latest_telemetry&.voltage_mv || 0
  end

  # Розрахунок заряду у % (Діапазон 3000мВ - 4200мВ)
  def charge_percentage
    return 0 if ionic_voltage.zero?

    # Масштабуємо: 3000мВ = 0%, 4200мВ = 100%
    ((ionic_voltage - 3000).to_f / 1200 * 100).clamp(0, 100).to_i
  end

  # Перевірка критичного рівня енергії для виживання вузла
  def low_power?
    ionic_voltage > 0 && ionic_voltage < 3300
  end

  # Помічник для швидкого доступу до останнього логу (мемоізований)
  def latest_telemetry
    @latest_telemetry ||= telemetry_logs.order(created_at: :desc).first
  end

  private

  def build_default_wallet
    create_wallet!(balance: 0)
  end

  def ensure_calibration
    create_device_calibration! unless device_calibration
  end

  def normalize_did
    self.did = did.to_s.strip.upcase if did.present?
  end
end

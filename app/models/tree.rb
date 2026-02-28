# frozen_string_literal: true

class Tree < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model, optional: true # [ПОКРАЩЕННЯ]: Дозволяємо посадку без моделі
  belongs_to :tree_family
  
  has_one :wallet, dependent: :destroy
  
  # Зв'язок для Zero-Trust шифрування (DID Солдата = device_uid ключа)
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :did, dependent: :destroy
  
  has_one :device_calibration, dependent: :destroy
  has_many :telemetry_logs, dependent: :destroy
  
  # [НОВЕ]: Зв'язок для тривог (EWS)
  has_many :ews_alerts, dependent: :destroy
  
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  
  # Поліморфний зв'язок для прогнозів та добових звітів
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- СТАН (The Lifecycle) ---
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  # --- КОЛБЕКИ ТА ВАЛІДАЦІЇ ---
  after_create :build_default_wallet
  after_create :ensure_calibration
  before_validation :normalize_did

  validates :did, presence: true, uniqueness: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true

  # --- СКОУПИ (The Watchers) ---
  scope :active, -> { where(status: :active) }
  scope :geolocated, -> { where.not(latitude: nil, longitude: nil) }
  # Дерева, які давно не виходили на зв'язок (Королева їх не бачила)
  scope :silent, -> { joins(:telemetry_logs).where("telemetry_logs.created_at < ?", 1.day.ago).distinct }

  # --- МЕТОДИ (Intelligence) ---

  def geolocated?
    latitude.present? && longitude.present?
  end

  def latest_log
    telemetry_logs.recent.first
  end

  # Останній розрахований індекс стресу (з AiInsight)
  def current_stress
    ai_insights.daily_health_summary.where(target_date: Date.yesterday).first&.stress_index || 0.0
  end

  # Чи є відкриті тривоги по цьому дереву?
  def under_threat?
    ews_alerts.unresolved.exists?
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

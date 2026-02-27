# frozen_string_literal: true

class Tree < ApplicationRecord
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model
  belongs_to :tree_family
  
  has_one :wallet, dependent: :destroy
  # [НОВЕ]: Зв'язок для Zero-Trust шифрування
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :did, dependent: :destroy
  
  has_one :device_calibration, dependent: :destroy
  has_many :telemetry_logs, dependent: :destroy
  has_many :maintenance_records, as: :maintainable
  
  # [НОВЕ]: Поліморфний зв'язок для прогнозів Атрактора
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # [НОВЕ]: Стан дерева (для аналітики та NaasContract)
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  after_create :build_default_wallet
  before_validation :normalize_did

  validates :did, presence: true, uniqueness: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: true, allow_nil: true

  def geolocated?
    latitude.present? && longitude.present?
  end

  # [НОВЕ]: Зручний хелпер для отримання останнього пульсу
  def latest_log
    telemetry_logs.recent.first
  end

  private

  def build_default_wallet
    create_wallet!(balance: 0)
  end

  def normalize_did
    self.did = did.to_s.strip.upcase if did.present?
  end
end

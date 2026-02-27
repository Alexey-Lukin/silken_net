# frozen_string_literal: true

class Tree < ApplicationRecord
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model
  belongs_to :tree_family
  
  has_one :wallet, dependent: :destroy
  has_one :device_calibration, dependent: :destroy
  has_many :telemetry_logs, dependent: :destroy
  has_many :maintenance_records, as: :maintainable

  after_create :build_default_wallet
  
  # Гарантуємо, що DID завжди в одинаковому форматі для швидкого пошуку
  before_validation :normalize_did

  # did - це 32-бітний хеш, згенерований в main.c з UID STM32 та шуму кристала
  validates :did, presence: true, uniqueness: true
  
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: true, allow_nil: true

  def geolocated?
    latitude.present? && longitude.present?
  end

  private

  def build_default_wallet
    create_wallet!(balance: 0)
  end

  def normalize_did
    self.did = did.to_s.strip.upcase if did.present?
  end
end

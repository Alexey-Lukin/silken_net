# frozen_string_literal: true

class Gateway < ApplicationRecord
  belongs_to :cluster, optional: true
  
  # Zero-Trust: Унікальний ключ для розшифровки батчів саме цієї Королеви
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy
  
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :destroy
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :actuators, dependent: :destroy

  before_validation :normalize_uid

  validates :uid, presence: true, uniqueness: true
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }
  
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: true, allow_nil: true

  scope :online, -> { where("last_seen_at >= ?", 1.hour.ago) }
  scope :offline, -> { where("last_seen_at < ? OR last_seen_at IS NULL", 1.hour.ago) }

  def mark_seen!
    touch(:last_seen_at)
  end

  def geolocated?
    latitude.present? && longitude.present?
  end

  def next_wakeup_expected_at
    last_seen_at ? last_seen_at + config_sleep_interval_s.seconds : nil
  end

  private

  def normalize_uid
    self.uid = uid.to_s.strip.upcase if uid.present?
  end
end

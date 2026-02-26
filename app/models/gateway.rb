# frozen_string_literal: true

class Gateway < ApplicationRecord
  belongs_to :cluster, optional: true
  # Пакети від дерев, що пройшли через цю Королеву
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  # Власні життєві показники Королеви (батарея, зв'язок)
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :destroy
  # Журнал фізичного обслуговування (хто і коли чистив сонячну панель)
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :actuators, dependent: :destroy

  validates :uid, presence: true, uniqueness: true
  # Валідації для управління стільниковою мережею та сном
  # phone_number та sim_iccid можуть бути порожніми до моменту встановлення SIM-карти
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }
  # Геопросторовий блок (для DSM та 3D-радіотрас)
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: true, allow_nil: true

  scope :online, -> { where("last_seen_at >= ?", 1.hour.ago) }
  scope :offline, -> { where("last_seen_at < ? OR last_seen_at IS NULL", 1.hour.ago) }

  def mark_seen!
    touch(:last_seen_at)
  end

  # Допоміжний метод перевірки, чи пристрій має фізичну прив'язку на карті
  def geolocated?
    latitude.present? && longitude.present?
  end

  # Метод для розрахунку наступного пробудження Королеви
  def next_wakeup_expected_at
    last_seen_at ? last_seen_at + config_sleep_interval_s.seconds : nil
  end
end

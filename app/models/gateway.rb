# frozen_string_literal: true

class Gateway < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true

  # Zero-Trust: Унікальний ключ для розшифровки батчів (DID Королеви = device_uid ключа)
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy

  # Телеметрія дерев та власна діагностика Королеви
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :destroy

  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :actuators, dependent: :destroy
  has_many :actuator_commands, through: :actuators

  # --- СТАНИ (The Sovereign States) ---
  enum :state, {
    idle: 0,        # Очікування / Сон
    active: 1,      # Передача телеметрії
    updating: 2,    # Прийом OTA чанків (Busy)
    maintenance: 3  # Технічне обслуговування
  }, default: :idle

  # --- КОЛБЕКИ ТА ВАЛІДАЦІЇ ---
  before_validation :normalize_uid

  validates :uid, presence: true, uniqueness: true
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }

  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  # IP адреса модему SIM7070G (Starlink/LTE)
  validates :ip_address, format: { with: Resolv::AddressRegex }, allow_blank: true

  # --- СКОУПИ (The Watchers) ---
  scope :online, -> { where("last_seen_at >= ?", 1.hour.ago) }
  scope :offline, -> { where("last_seen_at < ? OR last_seen_at IS NULL", 1.hour.ago) }
  scope :ready_for_commands, -> { idle.online }

  # --- МЕТОДИ (Intelligence) ---

  # Оновлення пульсу та мережевого якоря
  def mark_seen!(new_ip = nil)
    updates = { last_seen_at: Time.current }
    updates[:ip_address] = new_ip if new_ip.present? && ip_address != new_ip

    # Якщо Королева прокинулася, вона автоматично стає idle, якщо не оновлюється
    updates[:state] = :idle if state == "active" || state.nil?

    update!(updates)
  end

  def online?
    last_seen_at.present? && last_seen_at >= 1.hour.ago
  end

  def geolocated?
    latitude.present? && longitude.present?
  end

  # Розрахунок наступного вікна зв'язку (Projected Pulse)
  def next_wakeup_expected_at
    last_seen_at ? last_seen_at + config_sleep_interval_s.seconds : nil
  end

  # Чи потребує Королева уваги патрульного?
  def system_fault?
    cluster&.ews_alerts&.unresolved&.system_fault&.exists? || battery_critical?
  end

  # Швидка перевірка останнього рівня напруги
  def battery_critical?
    last_log = gateway_telemetry_logs.order(created_at: :desc).first
    last_log.present? && last_log.voltage_mv < 3300
  end

  private

  def normalize_uid
    self.uid = uid.to_s.strip.upcase if uid.present?
  end
end

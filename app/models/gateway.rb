# frozen_string_literal: true

class Gateway < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true
  
  # Zero-Trust: Унікальний ключ для розшифровки батчів саме цієї Королеви
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy
  
  # Телеметрія дерев, що пройшла через цей шлюз
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  
  # Власна телеметрія шлюзу (Battery, RSSI модема, Uptime)
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :destroy
  
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :actuators, dependent: :destroy
  has_many :actuator_commands, through: :actuators

  # --- СТАНИ (The Sovereign States) ---
  # idle - готовий до передачі, active - передає дані, 
  # updating - приймає OTA чанки, maintenance - тех. огляд
  enum :state, { idle: 0, active: 1, updating: 2, maintenance: 3 }, default: :idle

  # --- КОЛБЕКИ ТА ВАЛІДАЦІЇ ---
  before_validation :normalize_uid

  validates :uid, presence: true, uniqueness: true
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }
  
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  
  # IP адреса Starlink/LTE модема (оновлюється в UnpackTelemetryWorker)
  validates :ip_address, format: { with: Resolv::AddressRegex }, allow_blank: true

  # --- СКОУПИ (The Watchers) ---
  # Шлюз вважається онлайн, якщо був зв'язок протягом останньої години
  scope :online, -> { where("last_seen_at >= ?", 1.hour.ago) }
  scope :offline, -> { where("last_seen_at < ? OR last_seen_at IS NULL", 1.hour.ago) }
  scope :ready_for_commands, -> { idle.online }

  # --- МЕТОДИ (Intelligence) ---

  # Оновлення часу останнього контакту
  def mark_seen!(new_ip = nil)
    updates = { last_seen_at: Time.current }
    updates[:ip_address] = new_ip if new_ip.present? && ip_address != new_ip
    
    # Якщо шлюз був у стані спокою, позначаємо його як активний
    updates[:state] = :idle if state == nil
    
    update!(updates)
  end

  def geolocated?
    latitude.present? && longitude.present?
  end

  # Розрахунок наступного вікна зв'язку (для економії батареї на бекенді)
  def next_wakeup_expected_at
    last_seen_at ? last_seen_at + config_sleep_interval_s.seconds : nil
  end

  # Чи є критичні системні помилки в цьому шлюзі?
  def system_fault?
    # Шукаємо активні алерти типу system_fault, прив'язані до цього шлюзу через кластер
    cluster&.ews_alerts&.unresolved&.where(alert_type: :system_fault)&.exists?
  end

  private

  def normalize_uid
    self.uid = uid.to_s.strip.upcase if uid.present?
  end
end

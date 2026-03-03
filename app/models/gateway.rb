# frozen_string_literal: true

class Gateway < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true

  # Zero-Trust: Унікальний ключ для розшифровки батчів (DID Королеви = device_uid ключа)
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy

  # Телеметрія дерев та власна діагностика Королеви
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :delete_all

  # [ВИПРАВЛЕНО]: Знищення Журналу Обслуговування (Аудит).
  # Використовуємо :restrict_with_error, щоб зберегти історію витрат та ремонтів.
  # Королеву можна списати (status: :retired), але не можна видалити її минуле.
  has_many :maintenance_records, as: :maintainable, dependent: :restrict_with_error
  
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
  # [ВИПРАВЛЕНО]: Гнучкість "Смерті". Статус онлайн тепер динамічний.
  # Беремо інтервал сну конкретної Королеви + 20% люфту на затримку мережі/обробку.
  scope :online, -> {
    where("last_seen_at >= (CURRENT_TIMESTAMP - (config_sleep_interval_s * 1.2 || ' seconds')::interval)")
  }
  
  scope :offline, -> {
    where("last_seen_at IS NULL OR last_seen_at < (CURRENT_TIMESTAMP - (config_sleep_interval_s * 1.2 || ' seconds')::interval)")
  }
  
  scope :ready_for_commands, -> { idle.online }

  # --- МЕТОДИ (Intelligence) ---

  # Оновлення пульсу та мережевого якоря
  # [ВИПРАВЛЕНО]: Тепер приймає voltage для денормалізації (N+1 fix)
  def mark_seen!(new_ip: nil, voltage_mv: nil)
    updates = { last_seen_at: Time.current }
    updates[:ip_address] = new_ip if new_ip.present? && ip_address != new_ip
    updates[:latest_voltage_mv] = voltage_mv if voltage_mv.present?

    # Якщо Королева прокинулася, вона автоматично стає idle
    updates[:state] = :idle if %w[active].include?(state) || state.nil?

    update!(updates)
  end

  def online?
    return false if last_seen_at.nil?
    # Динамічна перевірка: чи не перевищено інтервал сну з люфтом
    last_seen_at >= (config_sleep_interval_s * 1.2).seconds.ago
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

  # [ВИПРАВЛЕНО]: Блискавична перевірка без SQL запитів до логів.
  # Використовуємо денормалізовану колонку latest_voltage_mv.
  def battery_critical?
    latest_voltage_mv.present? && latest_voltage_mv < 3300
  end

  private

  def normalize_uid
    self.uid = uid.to_s.strip.upcase if uid.present?
  end
end

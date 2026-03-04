# frozen_string_literal: true

class Gateway < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true

  # Zero-Trust: Унікальний ключ для розшифровки батчів (DID Королеви = device_uid ключа)
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy

  # Телеметрія дерев та власна діагностика Королеви
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :delete_all
  has_one :latest_gateway_telemetry_log, -> { order(created_at: :desc) },
          class_name: "GatewayTelemetryLog", foreign_key: :queen_uid, primary_key: :uid

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
    maintenance: 3, # Технічне обслуговування
    faulty: 4       # Апаратний збій / вичерпано ретраї OTA
  }, default: :idle

  # --- КОНСТАНТИ ---
  # Zero-Trust: Формат UID відповідає апаратній специфікації шлюзу (SNET-Q-[8 hex digits])
  UID_FORMAT = /\ASNET-Q-[0-9A-F]{8}\z/
  LOW_POWER_MV = 3300  # Поріг критичного рівня енергії (аналогічно Tree::LOW_POWER_MV)

  # --- КОЛБЕКИ ТА ВАЛІДАЦІЇ ---
  before_validation :normalize_uid

  validates :uid, presence: true, uniqueness: true,
            format: { with: UID_FORMAT, message: "має відповідати апаратному формату (SNET-Q-XXXXXXXX)" }
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }

  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  # IP адреса модему SIM7070G (Starlink/LTE)
  validates :ip_address, format: { with: Resolv::AddressRegex }, allow_blank: true

  # --- СКОУПИ (The Watchers) ---
  # [ВИПРАВЛЕНО]: Індексоване обчислення порогу (make_interval замість string-concat).
  # Беремо інтервал сну конкретної Королеви + 20% люфту на затримку мережі/обробку.
  scope :online, -> {
    where("last_seen_at >= CURRENT_TIMESTAMP - make_interval(secs => config_sleep_interval_s * 1.2)")
  }

  scope :offline, -> {
    where("last_seen_at IS NULL OR last_seen_at < CURRENT_TIMESTAMP - make_interval(secs => config_sleep_interval_s * 1.2)")
  }

  scope :ready_for_commands, -> { idle.online }

  # --- МЕТОДИ (Intelligence) ---

  # [ВИПРАВЛЕНО: Race Condition + Performance]:
  # GREATEST гарантує детермінованість при дубльованих пакетах через Starlink Direct to Cell.
  # update_all обходить колбеки ActiveRecord — блискавичне оновлення на hot path телеметрії.
  def mark_seen!(new_ip: nil, voltage_mv: nil)
    now = Time.current

    set_clauses = [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?)" ]
    bind_values = [ now, now ]

    if new_ip.present?
      set_clauses << "ip_address = ?"
      bind_values << new_ip
    end

    if voltage_mv.present?
      set_clauses << "latest_voltage_mv = ?"
      bind_values << voltage_mv
    end

    self.class.where(id: id).update_all([ set_clauses.join(", "), *bind_values ])

    # Синхронізуємо in-memory стан без reload для швидкодії на hot path
    self.last_seen_at = now
    self.ip_address = new_ip if new_ip.present?
    self.latest_voltage_mv = voltage_mv if voltage_mv.present?
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
    latest_voltage_mv.present? && latest_voltage_mv < LOW_POWER_MV
  end

  private

  def normalize_uid
    self.uid = uid.to_s.strip.upcase if uid.present?
  end
end

# frozen_string_literal: true

class Actuator < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  belongs_to :gateway
  has_one :cluster, through: :gateway
  has_many :commands, class_name: "ActuatorCommand", dependent: :destroy

  # --- ТИПИ ПРИСТРОЇВ (The Arsenal) ---
  enum :device_type, {
    water_valve: 0,     # Електромагнітний клапан (Посуха / Пожежа)
    fire_siren: 1,      # Звукова сирена (Вандалізм / Пожежа)
    seismic_beacon: 2,  # Світлозвуковий маяк
    drone_launcher: 3   # Док-станція дрона
  }, prefix: true

  # --- СТАНИ (The Readiness) ---
  enum :state, {
    idle: 0,
    active: 1,
    offline: 2,
    maintenance_needed: 3
  }

  # --- ВАЛІДАЦІЇ ---
  validates :name, :device_type, presence: true
  # endpoint - унікальний шлях CoAP на конкретній Королеві
  validates :endpoint, presence: true, uniqueness: { scope: :gateway_id }

  # Safety Envelope: фізичний ліміт безперервної роботи актуатора (секунди)
  validates :max_active_duration_s, numericality: { greater_than: 0 }, allow_nil: true
  # Energy Budget: орієнтовна витрата енергії за одну активацію (мДж)
  validates :estimated_mj_per_action, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :operational, -> { where(state: :idle) }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТА СТАТУСИ (AASM State Machine)
  # =========================================================================
  aasm column: :state, enum: true, whiny_persistence: true do
    state :idle, initial: true
    state :active
    state :offline
    state :maintenance_needed

    # Активація пристрою (виклик від ActuatorCommandWorker)
    event :activate do
      before do
        self.last_activated_at = Time.current
      end
      after do
        gateway.touch(:last_seen_at)
        Rails.logger.info "⚙️ [ACTUATOR] #{name} на шлюзі #{gateway.uid} АКТИВОВАНО."
      end
      transitions from: :idle, to: :active
    end

    # Повернення в режим очікування (The Reset)
    event :deactivate do
      after do
        Rails.logger.info "⚙️ [ACTUATOR] #{name} повернувся в стан спокою."
      end
      transitions from: [ :active, :offline ], to: :idle
    end

    # Пристрій втратив зв'язок
    event :go_offline do
      transitions from: [ :idle, :active ], to: :offline
    end

    # Критичний збій (The Hardware Fault)
    event :report_fault do
      after do |reason|
        reason ||= "Невідома помилка CoAP"
        if gateway.cluster_id.present?
          EwsAlert.create!(
            cluster: gateway.cluster,
            alert_type: :system_fault,
            severity: :critical,
            message: "Збій актуатора '#{name}' (#{endpoint}). Причина: #{reason}. Потрібен виїзд патруля."
          )
        end
        Rails.logger.error "🛠️ [ACTUATOR] #{name} ВИЙШОВ З ЛАДУ. Система EWS сповіщена."
      end
      transitions from: [ :idle, :active, :offline ], to: :maintenance_needed
    end
  end

  # Перевірка, чи пристрій готовий до негайного розгортання
  def ready_for_deployment?
    return false unless idle?

    # [СИНХРОНІЗОВАНО]: Шлюз має бути в мережі ТА не перебувати в стані оновлення
    gateway.online? && !gateway.updating?
  end

  # Backward-compatible wrappers для існуючих Workers
  def mark_active!
    activate!
  end

  def mark_idle!
    deactivate!
  end

  def require_maintenance!(reason = "Невідома помилка CoAP")
    report_fault!(reason)
  end
end

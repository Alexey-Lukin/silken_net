# frozen_string_literal: true

class Actuator < ApplicationRecord
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

  # --- СКОУПИ ---
  scope :operational, -> { where(state: :idle) }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТА СТАТУСИ
  # =========================================================================

  # Перевірка, чи пристрій готовий до негайного розгортання
  def ready_for_deployment?
    return false unless state_idle?

    # [СИНХРОНІЗОВАНО]: Шлюз має бути в мережі ТА не перебувати в стані оновлення
    gateway.online? && !gateway.state_updating?
  end

  # Фіксація початку роботи (The Pulse of Action)
  def mark_active!
    transaction do
      update!(state: :active, last_activated_at: Time.current)
      # Оновлюємо пульс шлюзу, оскільки активація актуатора — це теж мережева активність
      gateway.touch(:last_seen_at)
    end
    Rails.logger.info "⚙️ [ACTUATOR] #{name} на шлюзі #{gateway.uid} АКТИВОВАНО."
  end

  # Повернення в режим очікування (The Reset)
  def mark_idle!
    update!(state: :idle)
    Rails.logger.info "⚙️ [ACTUATOR] #{name} повернувся в стан спокою."
  end

  # Критичний збій (The Hardware Fault)
  def require_maintenance!(reason = "Невідома помилка CoAP")
    transaction do
      update!(state: :maintenance_needed)

      # [СИНХРОНІЗОВАНО]: Створюємо системну тривогу через EwsAlert
      EwsAlert.create!(
        cluster: cluster,
        alert_type: :system_fault,
        severity: :critical,
        message: "Збій актуатора '#{name}' (#{endpoint}). Причина: #{reason}. Потрібен виїзд патруля."
      )
    end

    Rails.logger.error "🛠️ [ACTUATOR] #{name} ВИЙШОВ З ЛАДУ. Система EWS сповіщена."
  end
end

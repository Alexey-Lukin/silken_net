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

  # Safety Envelope: фізичний ліміт безперервної роботи актуатора (секунди)
  validates :max_active_duration_s, numericality: { greater_than: 0 }, allow_nil: true
  # Energy Budget: орієнтовна витрата енергії за одну активацію (мДж)
  validates :estimated_mj_per_action, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :operational, -> { where(state: :idle) }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТА СТАТУСИ
  # =========================================================================

  # Перевірка, чи пристрій готовий до негайного розгортання
  def ready_for_deployment?
    return false unless idle?

    # [СИНХРОНІЗОВАНО]: Шлюз має бути в мережі ТА не перебувати в стані оновлення
    gateway.online? && !gateway.updating?
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

      # [N+1 FIX]: Перевіряємо наявність кластера через gateway.cluster_id
      # замість has_one :through, щоб не створювати зайвий JOIN.
      return unless gateway.cluster_id.present?

      # [СИНХРОНІЗОВАНО]: Створюємо системну тривогу через EwsAlert
      EwsAlert.create!(
        cluster: gateway.cluster,
        alert_type: :system_fault,
        severity: :critical,
        message: "Збій актуатора '#{name}' (#{endpoint}). Причина: #{reason}. Потрібен виїзд патруля."
      )
    end

    Rails.logger.error "🛠️ [ACTUATOR] #{name} ВИЙШОВ З ЛАДУ. Система EWS сповіщена."
  end
end

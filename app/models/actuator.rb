# frozen_string_literal: true

class Actuator < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :gateway
  has_many :commands, class_name: "ActuatorCommand", dependent: :destroy

  # --- ТИПИ ПРИСТРОЇВ (The Arsenal) ---
  enum :device_type, {
    water_valve: 0,     # Електромагнітний клапан (Посуха / Пожежа)
    fire_siren: 1,      # Звукова сирена (Вандалізм)
    seismic_beacon: 2,  # Світлозвуковий маяк
    drone_launcher: 3   # Док-станція дрона-розвідника
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
  # endpoint - це шлях на CoAP сервері Королеви (напр. "valve_a", "siren_1")
  validates :endpoint, presence: true, uniqueness: { scope: :gateway_id }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТА СТАТУСИ
  # =========================================================================

  # Перевірка, чи пристрій фізично та мережево готовий до виконання наказу
  def ready_for_deployment?
    state_idle? && gateway.last_seen_at.present? && gateway.last_seen_at > 1.hour.ago
  end

  # Фіксація початку роботи
  def mark_active!
    update!(state: :active, last_activated_at: Time.current)
    Rails.logger.info "⚙️ [ACTUATOR] #{name} переведено в режим ACTIVE."
  end

  # Повернення в режим очікування (викликається після підтвердження від Королеви)
  def mark_idle!
    update!(state: :idle)
    Rails.logger.info "⚙️ [ACTUATOR] #{name} завершив роботу і повернувся в IDLE."
  end

  # Переведення в сервісний режим (наприклад, якщо CoAP-команда повернула помилку 3 рази)
  def require_maintenance!
    update!(state: :maintenance_needed)
    # Тут можна додати генерацію EwsAlert для інженера
    Rails.logger.warn "🛠️ [ACTUATOR] #{name} потребує технічного обслуговування!"
  end
end

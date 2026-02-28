# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Тривога ЗАВЖДИ належить кластеру, щоб Оракул знав, кому слати SMS
  belongs_to :cluster
  
  # Тривога МОЖЕ належати дереву (біологія) або бути системною (шлюз/актуатор)
  belongs_to :tree, optional: true

  # Якщо тривога закрита патрульним після ремонту, фіксуємо його
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true

  # --- СТАТУСИ ТА РІВНІ ---
  enum :status, { active: 0, resolved: 1, ignored: 2 }, prefix: true
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    insect_epidemic: 1,   # Короїд (TinyML)
    vandalism_breach: 2,  # Відкриття корпусу / Пил
    fire_detected: 3,     # Пожежа
    seismic_anomaly: 4,   # Землетрус (П'єзо)
    hardware_fault: 5     # [ОНОВЛЕНО] Втрата зв'язку / Поломка актуатора
  }, prefix: true

  # Використовуємо message, оскільки саме його ми передаємо у Telegram/SMS воркерах
  validates :severity, :alert_type, :message, presence: true

  # --- СКОУПИ ---
  scope :unresolved, -> { status_active }
  scope :critical, -> { severity_critical.unresolved }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ІНЦИДЕНТУ
  # =========================================================================

  def resolve!(user: nil, notes: "Закрито системою")
    update!(
      status: :resolved,
      resolved_at: Time.current,
      resolved_by: user&.id,
      resolution_notes: notes
    )
    Rails.logger.info "🛡️ [EWS] Тривогу ##{id} (#{alert_type}) успішно закрито."
  end

  # Хелпер для сумісності з логікою MaintenanceRecord
  def resolved?
    status_resolved?
  end
end

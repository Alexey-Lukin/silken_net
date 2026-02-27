# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  belongs_to :tree
  # Рівень критичності
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  # [СИНХРОНІЗОВАНО] Типи загроз, які приходять з AlertDispatchService
  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    insect_epidemic: 1,   # Короїд (TinyML)
    vandalism_breach: 2,  # Відкриття корпусу / Пил
    fire_detected: 3,     # Пожежа
    seismic_anomaly: 4,   # Землетрус (П'єзо)
    system_fault: 5       # Втрата зв'язку
  }, prefix: true

  validates :severity, :alert_type, :description, presence: true

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :critical, -> { severity_critical.unresolved }

  def resolve!
    update!(resolved_at: Time.current)
  end
end

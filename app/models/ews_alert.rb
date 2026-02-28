# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :cluster
  belongs_to :tree, optional: true
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true

  # --- СТАТУСИ ТА РІВНІ ---
  enum :status, { active: 0, resolved: 1, ignored: 2 }, prefix: true
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    insect_epidemic: 1,   # Короїд (TinyML)
    vandalism_breach: 2,  # Відкриття корпусу
    fire_detected: 3,     # Пожежа
    seismic_anomaly: 4,   # Землетрус
    system_fault: 5       # [СИНХРОНІЗОВАНО]: Поломка шлюзу/актуатора/сенсора
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :severity, :alert_type, :message, presence: true

  # --- КОЛБЕКИ (Zero-Lag Awareness) ---
  # Як тільки тривога зафіксована в БД — гінці (Sidekiq) стають на крило
  after_create_commit :dispatch_notifications!

  # --- СКОУПИ ---
  scope :unresolved, -> { status_active }
  scope :critical, -> { severity_critical.unresolved }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # =========================================================================
  # МЕТОДИ (The Lens of Truth)
  # =========================================================================

  def resolve!(user: nil, notes: "Закрито системою")
    update!(
      status: :resolved,
      resolved_at: Time.current,
      resolver: user,
      resolution_notes: notes
    )
    # Також можемо автоматично закривати пов'язані MaintenanceRecord тут
  end

  # Точка на мапі для десанту Патрульних
  def coordinates
    return [ tree.latitude, tree.longitude ] if tree.present?

    # Якщо тривога системна для шлюзу, беремо центр кластера (geojson_polygon)
    # або координати першого ліпшого шлюзу кластера.
    cluster.gateways.first&.then { |g| [ g.latitude, g.longitude ] }
  end

  # Чи потребує цей інцидент негайного втручання актуаторів?
  def actionable?
    severity_critical? && (alert_type_fire_detected? || alert_type_severe_drought?)
  end

  private

  def dispatch_notifications!
    # Викликаємо наш AlertNotificationWorker, який ми зашліфували раніше
    AlertNotificationWorker.perform_async(self.id)
  end
end

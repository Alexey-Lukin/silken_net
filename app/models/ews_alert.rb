# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :cluster
  belongs_to :tree, optional: true
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true

  # --- СТАТУСИ ТА РІВНІ ---
  # [СИНХРОНІЗОВАНО]: prefix: true гарантує виклики status_active? та status_resolved?
  enum :status, { active: 0, resolved: 1, ignored: 2 }, prefix: true
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    insect_epidemic: 1,   # Короїд (TinyML)
    vandalism_breach: 2,  # Відкриття корпусу
    fire_detected: 3,     # Пожежа
    seismic_anomaly: 4,   # Землетрус
    system_fault: 5       # Поломка шлюзу/актуатора/сенсора
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :severity, :alert_type, :message, presence: true

  # --- КОЛБЕКИ (Zero-Lag Awareness) ---
  # Сакральна асинхронність: сповіщення летять лише після COMMIT
  after_create_commit :dispatch_notifications!

  # Миттєве оновлення мапи та стрічки новин у Цитаделі
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # --- СКОУПИ ---
  scope :unresolved, -> { status_active }
  scope :critical, -> { severity_critical.unresolved }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # =========================================================================
  # МЕТОДИ (The Lens of Truth)
  # =========================================================================

  # Протокол завершення інциденту
  def resolve!(user: nil, notes: "Закрито системою")
    # [СИНХРОНІЗАЦІЯ З REDIS]: Знімаємо "режим тиші", щоб Оракул знову міг 
    # слухати це дерево після його відновлення.
    clear_silence_filter!

    update!(
      status: :resolved,
      resolved_at: Time.current,
      resolver: user,
      resolution_notes: notes
    )

    # [SELF-HEALING]: Атомарно закриваємо MaintenanceRecord
    close_associated_maintenance!
  end

  # [ВИПРАВЛЕНО]: Навігація в тумані. 
  # Якщо дерево втратило GPS, ми фокусуємо патруль на центрі сили кластера.
  def coordinates
    if tree&.latitude.present? && tree&.longitude.present?
      [ tree.latitude, tree.longitude ]
    elsif (center = cluster.geo_center)
      [ center[:lat], center[:lng] ]
    else
      # Нульова точка для запобігання помилкам Leaflet.js
      [ 0.0, 0.0 ]
    end
  end

  # Чи потребує цей інцидент негайного втручання актуаторів?
  def actionable?
    severity_critical? && (alert_type_fire_detected? || alert_type_severe_drought?)
  end

  private

  def dispatch_notifications!
    AlertNotificationWorker.perform_async(self.id)
  end

  # [ОПТИМІЗАЦІЯ]: Очищення Redis-блокувальника
  def clear_silence_filter!
    return unless tree_id.present?

    silence_key = "ews_silence:#{tree_id}:#{alert_type}"
    Rails.cache.delete(silence_key)
  end

  # [ВИПРАВЛЕНО]: Turbo Transmission. 
  # Видаляємо тривогу зі стрічки новин (Live Feed), як тільки вона вирішена.
  def broadcast_status_change
    # Оновлення бейджа статусу на карті/деталях
    Turbo::StreamsChannel.broadcast_replace_to(
      "ews_updates_#{cluster_id}",
      target: "alert_#{id}",
      html: Views::Components::Alerts::Badge.new(alert: self).call
    )

    # Повне видалення вирішеного інциденту з Live Feed Архітектора
    if status_resolved?
      Turbo::StreamsChannel.broadcast_remove_to(
        "ews_live_feed",
        target: "alert_row_#{id}"
      )
    end
  end

  def close_associated_maintenance!
    # Використовуємо update_all для швидкодії без запуску зайвих колбеків моделей
    MaintenanceRecord.where(ews_alert_id: id).where.not(status: :completed).update_all(
      status: :completed,
      performed_at: Time.current,
      notes: "Auto-resolved via EWS Recovery Protocol"
    ) rescue nil
  end
end

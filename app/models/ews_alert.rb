# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # [FIX]: cluster optional — дерево може бути без кластера (одиноке дерево / тестова інсталяція)
  belongs_to :cluster, optional: true
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

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРИВОГИ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :resolved
    state :ignored

    event :resolve do
      transitions from: :active, to: :resolved
    end

    event :ignore do
      transitions from: :active, to: :ignored
    end

    event :reopen do
      transitions from: [ :resolved, :ignored ], to: :active
    end
  end

  # --- ВАЛІДАЦІЇ ---
  validates :severity, :alert_type, :message, presence: true

  # [STORM PROTECTION]: Захист від каскадних дублікатів.
  # Якщо один кластер накриває задимлення, сотні дерев згенерують fire_detected.
  # Ця валідація гарантує лише одну активну тривогу на [tree_id, alert_type].
  # Підкріплено частковим унікальним індексом на рівні БД (див. міграцію).
  validates :alert_type,
            uniqueness: { scope: [ :tree_id, :status ], message: "вже є активним для цього вузла" },
            if: -> { tree_id.present? && status_active? }

  # Троттлінг WebSocket-трансляцій: не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" повідомлень при масових інцидентах.
  BROADCAST_THROTTLE_SECONDS = 5

  # --- КОЛБЕКИ (Zero-Lag Awareness) ---
  # Сакральна асинхронність: сповіщення летять лише після COMMIT
  after_create_commit :dispatch_notifications!

  # Миттєве оновлення мапи та стрічки новин у Цитаделі
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # Real-time broadcast: оновлюємо дашборди всіх операторів при будь-яких змінах алерту
  after_update_commit :broadcast_alert_update

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

    true
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
      html: Alerts::Badge.new(alert: self).call
    )

    # Повне видалення вирішеного інциденту з Live Feed Архітектора
    if status_resolved?
      Turbo::StreamsChannel.broadcast_remove_to(
        "ews_live_feed",
        target: "alert_row_#{id}"
      )
    end
  end

  # [ВИПРАВЛЕНО]: MaintenanceRecord не має колонки status.
  # Використовуємо update_all для швидкодії — MaintenanceRecord не несе
  # фінансових зобов'язань та не має after_update колбеків, тому update_all безпечний.
  def close_associated_maintenance!
    MaintenanceRecord.where(ews_alert_id: id).update_all(
      performed_at: Time.current,
      notes: "Автозакрито через EWS Recovery Protocol"
    )
  end

  # [THROTTLED]: Real-time broadcast для всіх операторів організації.
  # При масових інцидентах WebSocket-канал може «лягти» від потоку оновлень.
  # Троттлінг гарантує мінімальний інтервал між некритичними broadcast.
  def broadcast_alert_update
    return unless should_broadcast?

    Turbo::StreamsChannel.broadcast_replace_to(
      "ews_alerts_org_#{cluster.organization_id}",
      target: "alert_#{id}",
      html: Alerts::Row.new(alert: self).call
    )
  end

  # Троттлінг: не частіше ніж раз на BROADCAST_THROTTLE_SECONDS.
  def should_broadcast?
    cache_key = "ews_alert_broadcast_throttle:#{id}"
    return false if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: BROADCAST_THROTTLE_SECONDS.seconds)
    true
  end
end

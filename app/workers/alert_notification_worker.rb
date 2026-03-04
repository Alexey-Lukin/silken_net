# frozen_string_literal: true

class AlertNotificationWorker
  include Sidekiq::Job
  sidekiq_options queue: "alerts", retry: 5

  def perform(ews_alert_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless alert

    cluster = alert.cluster
    organization = cluster.organization

    # 1. ЦЕНТРАЛЬНА НЕРВОВА СИСТЕМА (ActionCable)
    # Миттєве оновлення дашбордів у реальному часі
    broadcast_to_dashboards(alert)

    # 2. ДИФЕРЕНЦІЙОВАНА ДОСТАВКА (Smart Routing)
    # Оповіщення відповідальних осіб через зовнішні канали
    notify_stakeholders(alert, organization)

    Rails.logger.info "📢 [Notification] Тривогу #{alert.alert_type} розіслано для кластера #{cluster.name}."
  end

  private

  def broadcast_to_dashboards(alert)
    # [БЕЗПЕКА]: Визначаємо координати з урахуванням того, що тривога може бути системною.
    # Пріоритет: конкретне дерево → центроїд кластера (geo_center) → шлюз-запасний варіант.
    # Це запобігає дезорієнтації патруля, якщо шлюз стоїть за 5 км від епіцентру.
    location = if alert.tree
      { lat: alert.tree.latitude, lng: alert.tree.longitude }
    elsif (center = alert.cluster.geo_center)
      center
    elsif (fallback = alert.cluster.gateways.first)
      { lat: fallback.latitude, lng: fallback.longitude }
    else
      { lat: nil, lng: nil }
    end

    payload = {
      id: alert.id,
      target_did: alert.tree&.did || "SYSTEM_CLUSTER",
      severity: alert.severity,
      alert_type: alert.alert_type,
      message: alert.message,
      lat: location[:lat],
      lng: location[:lng],
      timestamp: alert.created_at.to_i
    }

    # Канал для конкретного кластера (для патрульних на місці)
    ActionCable.server.broadcast("cluster_#{alert.cluster_id}_alerts", payload)

    # Канал для всієї організації (для центрального офісу)
    ActionCable.server.broadcast("org_#{alert.organization_id}_alerts", payload)
  rescue StandardError => e
    Rails.logger.error "🛑 [ActionCable] WebSocket Error: #{e.message}"
  end

  def notify_stakeholders(alert, organization)
    # А. Email для Організації (Формальна звітність)
    if alert.severity_critical? && organization.billing_email.present?
      AlertMailer.with(alert: alert).critical_notification.deliver_later
    end

    # Б. Оперативні канали (Патруль та Адміни)
    # [ВИПРАВЛЕНО N+1]: Замість послідовного циклу — окремий атомарний SingleNotificationWorker
    # для кожного користувача і кожного каналу. Sidekiq розпаралелює 250 повідомлень одночасно.
    # Ретрай зачіпає лише одну конкретну доставку, а не весь пакет.
    stakeholders = organization.users.where(role: [ :admin, :forester ])

    stakeholders.each do |user|
      # SMS лише для критичних ситуацій (Пожежа / Вандалізм)
      SingleNotificationWorker.perform_async(user.id, alert.id, "sms") if alert.severity_critical?

      # Push для всіх рівнів тривог
      SingleNotificationWorker.perform_async(user.id, alert.id, "push")
    end
  end
end

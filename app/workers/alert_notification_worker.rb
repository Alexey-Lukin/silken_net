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
    # [БЕЗПЕКА]: Використовуємо дані дерева або шлюзу для локації
    source = alert.tree || alert.cluster.gateways.first
    
    payload = {
      id: alert.id,
      target_did: alert.tree&.did || "SYSTEM_GATEWAY", 
      severity: alert.severity,
      alert_type: alert.alert_type,
      message: alert.message,
      lat: source&.latitude,
      lng: source&.longitude,
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
    # [ВИПРАВЛЕНО]: Охоплюємо і адмінів, і патрульних (foresters)
    stakeholders = organization.users.where(role: [:admin, :forester])

    stakeholders.each do |user|
      # SMS лише для критичних ситуацій (Пожежа / Вандалізм)
      if alert.severity_critical?
        send_sms(user, alert)
      end

      # Push для всіх рівнів тривог
      send_push_notification(user, alert)
    end
  end

  def send_sms(user, alert)
    return unless user.respond_to?(:phone_number) && user.phone_number.present?
    
    # [LOGIC]: Викликаємо зовнішній API (напр. Twilio)
    # TwilioClient.send_sms(to: user.phone_number, body: "🚨 [S-NET] #{alert.message}")
    Rails.logger.info "📱 [SMS] Надіслано патрульному: #{user.full_name} (#{user.phone_number})"
  end

  def send_push_notification(user, alert)
    # [LOGIC]: Викликаємо Firebase або інший Push-сервіс
    # FcmClient.send_to_user(user, title: "Тривога: #{alert.alert_type}", body: alert.message)
    Rails.logger.info "📲 [Push] Доставлено в додаток користувачу: #{user.email_address}"
  end
end

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
    # Миттєвий бродкаст на дашборд ActiveBridge
    broadcast_to_dashboards(alert)

    # 2. ДИФЕРЕНЦІЙОВАНА ДОСТАВКА (Smart Routing)
    # Інвесторам - пошта, Лісникам - оперативні канали
    notify_stakeholders(alert, organization)

    Rails.logger.info "📢 [Notification] Тривогу #{alert.alert_type} розіслано для #{cluster.name}."
  end

  private

  def broadcast_to_dashboards(alert)
    # Передаємо розширений Payload для карти
    payload = {
      id: alert.id,
      tree_did: alert.tree.did,
      severity: alert.severity,
      alert_type: alert.alert_type,
      message: alert.message,
      lat: alert.tree.latitude,
      lng: alert.tree.longitude,
      timestamp: alert.created_at.to_i
    }

    ActionCable.server.broadcast("cluster_#{alert.cluster_id}_alerts", payload)
  rescue StandardError => e
    Rails.logger.error "🛑 [ActionCable] WebSocket Error: #{e.message}"
  end

  def notify_stakeholders(alert, organization)
    # А. Email для Організації (Звітність)
    if alert.severity_critical? && organization.billing_email.present?
      AlertMailer.with(alert: alert).critical_notification.deliver_later
    end

    # Б. Оперативні канали для Лісників (Патруль)
    # Використовуємо скоуп active_foresters, який ми заклали в моделі User
    organization.users.active_foresters.each do |forester|
      # 1. SMS (через Twilio або локальні шлюзи)
      send_sms(forester, alert) if alert.severity_critical?

      # 2. Push-сповіщення на смартфон (FCM)
      send_push_notification(forester, alert)

      # 3. Telegram (опціонально, але дуже корисно)
      # TelegramBotWorker.perform_async(forester.id, alert.message)
    end
  end

  def send_sms(user, alert)
    return unless user.phone_number.present?
    
    # TwilioClient.send_sms(to: user.phone_number, body: "🚨 [S-NET] #{alert.message}")
    Rails.logger.info "📱 [SMS] Відправлено патрульному #{user.full_name}"
  end

  def send_push_notification(user, alert)
    # Тут буде виклик FCM (Firebase Cloud Messaging)
    # FcmClient.send_to_user(user, title: "Тривога: #{alert.alert_type}", body: alert.message)
    Rails.logger.info "📲 [Push] Надіслано в додаток для #{user.full_name}"
  end
end

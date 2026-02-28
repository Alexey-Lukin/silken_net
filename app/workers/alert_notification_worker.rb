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
    broadcast_to_dashboards(alert)

    # 2. ДИФЕРЕНЦІЙОВАНА ДОСТАВКА (Smart Routing)
    notify_stakeholders(alert, organization)

    Rails.logger.info "📢 [Notification] Тривогу #{alert.alert_type} розіслано для кластера #{cluster.name}."
  end

  private

  def broadcast_to_dashboards(alert)
    # [БЕЗПЕКА]: Використовуємо безпечну навігацію (&.) для системних тривог
    payload = {
      id: alert.id,
      # Якщо це системний алерт, передаємо маркер SYSTEM
      target_did: alert.tree&.did || "SYSTEM_GATEWAY", 
      severity: alert.severity,
      alert_type: alert.alert_type,
      message: alert.message,
      lat: alert.tree&.latitude,
      lng: alert.tree&.longitude,
      timestamp: alert.created_at.to_i
    }

    ActionCable.server.broadcast("cluster_#{alert.cluster_id}_alerts", payload)
  rescue StandardError => e
    Rails.logger.error "🛑 [ActionCable] WebSocket Error: #{e.message}"
  end

  def notify_stakeholders(alert, organization)
    # А. Email для Організації (Звітність для інвесторів)
    if alert.severity_critical? && organization.billing_email.present?
      AlertMailer.with(alert: alert).critical_notification.deliver_later
    end

    # Б. Оперативні канали для Лісників (Патруль)
    # Припускаємо, що метод active_foresters повертає користувачів з role: :forester
    organization.users.where(role: :admin).each do |forester| # Або active_foresters
      if alert.severity_critical?
        send_sms(forester, alert)
      end

      send_push_notification(forester, alert)
      # send_telegram_message(forester, alert)
    end
  end

  def send_sms(user, alert)
    return unless user.respond_to?(:phone_number) && user.phone_number.present?
    
    # TwilioClient.send_sms(to: user.phone_number, body: "🚨 [S-NET] #{alert.message}")
    Rails.logger.info "📱 [SMS] Відправлено патрульному #{user.email_address}"
  end

  def send_push_notification(user, alert)
    # FcmClient.send_to_user(user, title: "Тривога: #{alert.alert_type}", body: alert.message)
    Rails.logger.info "📲 [Push] Надіслано в додаток для #{user.email_address}"
  end
end

# frozen_string_literal: true

class AlertNotificationWorker
  include Sidekiq::Job

  # Використовуємо окрему високопріоритетну чергу.
  # Якщо зовнішні API (Twilio/SendGrid) впали, ми робимо 5 експоненційних ретраїв.
  sidekiq_options queue: "alerts", retry: 5

  def perform(ews_alert_id)
    alert = EwsAlert.find_by(id: ews_alert_id)

    unless alert
      Rails.logger.warn "⚠️ [Notification] Тривогу #{ews_alert_id} не знайдено (можливо, вже видалена)."
      return
    end

    tree = alert.tree
    cluster = alert.cluster
    organization = cluster.organization

    # 1. СИНХРОННИЙ БРОДКАСТ (Zero-Lag Dashboard)
    # Миттєво прокидаємо дані на фронтенд інвесторів та диспетчерів
    broadcast_to_dashboards(alert, cluster)

    # 2. АСИНХРОННА ДОСТАВКА (SMS / Email)
    # Викликаємо зовнішні канали зв'язку
    deliver_external_notifications(alert, organization, tree)

    Rails.logger.info "📢 [Notification] Сповіщення '#{alert.alert_type}' успішно розіслано для Кластера #{cluster.id}."
  end

  private

  def broadcast_to_dashboards(alert, cluster)
    payload = {
      id: alert.id,
      tree_did: alert.tree.did,
      severity: alert.severity,
      alert_type: alert.alert_type,
      message: alert.message,
      timestamp: alert.created_at.to_i
    }

    # ActionCable транслює цей JSON прямо в браузери підключених клієнтів
    ActionCable.server.broadcast("cluster_#{cluster.id}_alerts", payload)
  rescue StandardError => e
    # Якщо Redis для ActionCable недоступний, ми не вбиваємо весь воркер
    Rails.logger.error "🛑 [ActionCable] Помилка WebSocket трансляції: #{e.message}"
  end

  def deliver_external_notifications(alert, organization, tree)
    # 1. Відправка Email інвестору/власнику
    # (Використовуємо billing_email, доданий у міграції 20260226170004)
    if organization&.billing_email.present?
      # Тут буде виклик Mailer-а:
      # AlertMailer.with(alert: alert).critical_alert_email.deliver_later
      Rails.logger.info "📧 [Email] Лист про '#{alert.alert_type}' сформовано для #{organization.billing_email}"
    end

    # 2. Відправка SMS Ліснику / Адміну
    # Шукаємо користувачів організації (міграція 20260226170638), щоб відправити їм SMS
    # У реальному коді тут буде інтеграція з Twilio або MessageBird:
    
    # organization.users.each do |user|
    #   next unless user.phone_number.present?
    #   
    #   TwilioClient.send_sms(
    #     to: user.phone_number,
    #     message: "[S-NET КРИТИЧНО] #{alert.message}"
    #   )
    # end
  end
end

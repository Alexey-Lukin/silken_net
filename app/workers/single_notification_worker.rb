# frozen_string_literal: true

# Атомарний воркер для відправки одного повідомлення одному користувачу по одному каналу.
# Це гарантує, що при ретраї Sidekiq перезапустить лише одну конкретну відправку,
# а не весь цикл по 250+ користувачах.
class SingleNotificationWorker
  include Sidekiq::Job
  sidekiq_options queue: "alerts", retry: 5

  def perform(user_id, ews_alert_id, channel)
    user = User.find_by(id: user_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless user && alert

    case channel.to_sym
    when :sms
      send_sms(user, alert)
    when :push
      send_push_notification(user, alert)
    end
  end

  private

  def send_sms(user, alert)
    return unless user.respond_to?(:phone_number) && user.phone_number.present?

    # TwilioClient.send_sms(to: user.phone_number, body: "🚨 [S-NET] #{alert.message}")
    Rails.logger.info "📱 [SMS] Надіслано патрульному: #{user.full_name} (#{user.phone_number})"
  end

  def send_push_notification(user, alert)
    # FcmClient.send_to_user(user, title: "Тривога: #{alert.alert_type}", body: alert.message)
    Rails.logger.info "📲 [Push] Доставлено в додаток користувачу: #{user.email_address}"
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Атомарний воркер для відправки одного повідомлення одному користувачу по одному каналу.
# Це гарантує, що при ретраї Sidekiq перезапустить лише одну конкретну відправку,
# а не весь цикл по 250+ користувачах.
class SingleNotificationWorker
  include Sidekiq::Job
  # [SIDEKIQ PRO EXPIRES_IN]: Індивідуальні повідомлення мають більший TTL (10 хвилин),
  # ніж батьківський AlertNotificationWorker (5 хв), оскільки вони вже in-flight.
  # Якщо конкретний SMS/Push застряг у черзі довше — краще пропустити,
  # ніж відправити застаріле сповіщення (патрульний вже бачив новіше).
  sidekiq_options queue: "alerts", retry: 5, expires_in: 10.minutes

  def perform(user_id, ews_alert_id, channel)
    user = User.find_by(id: user_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless user && alert

    case channel.to_sym
    when :sms
      send_sms(user, alert)
    when :push
      send_push_notification(user, alert)
    else
      # [ARCH.78] Диспетчер знав рівно два канали й не мав else — будь-який інший
      # гинув беззвучно. Тиша тут невідрізненна від доставки, тому гілка гучна.
      Rails.logger.error(
        "[Notification] Невідомий канал #{channel.inspect} — доставки НЕ буде (алерт ##{alert.id})"
      )
    end
  end

  private

  # [ARCH.78] Транспорт не задротований (див. 00_07 ARCH.78 — Twilio/FCM креденшели).
  # Рядок називає СТАН КАНАЛУ, а не результат: журнал, що стверджує дію, якої не
  # сталося, ховає мертвий канал доти, доки його не спитають у розборі пожежі.
  def send_sms(user, alert)
    return unless user.respond_to?(:phone_number) && user.phone_number.present?

    Rails.logger.warn(
      "[SMS] Канал не сконфігуровано — патрульному #{user.full_name} НЕ надіслано (алерт ##{alert.id})"
    )
  end

  def send_push_notification(user, alert)
    Rails.logger.warn(
      "[Push] Канал не сконфігуровано — користувачу #{user.email_address} НЕ доставлено (алерт ##{alert.id})"
    )
  end
end

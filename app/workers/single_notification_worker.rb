# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Атомарний воркер для відправки одного повідомлення одному користувачу по одному каналу.
# Це гарантує, що при ретраї Sidekiq перезапустить лише одну конкретну відправку,
# а не весь цикл по 250+ користувачах.
class SingleNotificationWorker
  include Sidekiq::Job
  # [SIDEKIQ PRO EXPIRES_IN]: Індивідуальні повідомлення мають більший TTL (10 хвилин),
  # ніж батьківський AlertNotificationWorker (5 хв), оскільки вони вже in-flight.
  # Якщо конкретне повідомлення застрягло в черзі довше — краще пропустити,
  # ніж відправити застаріле сповіщення (патрульний вже бачив новіше).
  # ⚠️ У OSS-редакції (поточній) опція **інертна** — активується лише з Sidekiq Pro
  # (DOC-R.10, `04_02 §11`). Намір вище виконує семантичний гард у `perform`, не вона.
  sidekiq_options queue: "alerts", retry: 5, expires_in: 10.minutes

  # [ARCH.78, присуд 2026-08-20] SMS-гілки більше немає: канал відкинуто разом
  # із `users.phone_number`. ⚫ Telegram знято ⚖️ 2026-09-06 [ARCH.60] — з не-поштових
  # каналів лишився сам `:push`, який чекає на FCM-адаптер [ARCH.108].
  def perform(user_id, ews_alert_id, channel)
    user = User.find_by(id: user_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless user && alert

    # 🔴 [ARCH.59] Той самий семантичний гард, що в батьківському воркері, і тут
    # він НЕ дубль, а backstop із власною підставою: батько судить стан один раз
    # на весь фан-аут, а ця джоба лежить у черзі ВДВІЧІ довше (пор. `expires_in`
    # вище) і виконується вже після нього — тобто резолв міг статися між ними.
    # Періметр класу = батько ⊥ дитина, як для `DeliveryChannels.available?`.
    unless alert.status_active?
      Rails.logger.info(
        "[Notification] Алерт ##{alert.id} уже #{alert.status} — канал #{channel} не задіюю."
      )
      return
    end

    case channel.to_sym
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

  # [ARCH.78] Транспорт не задротований (FCM-адаптер — за ⚖️-присудом про push,
  # gated [`ARCH.108`] — форма клієнта; реф перецілено з E.20 2026-08-24). Рядок
  # називає СТАН КАНАЛУ, а не результат: журнал, що стверджує
  # дію, якої не сталося, ховає мертвий канал доти, доки його не спитають у
  # розборі пожежі.
  def send_push_notification(user, alert)
    Rails.logger.warn(
      "[Push] Канал не сконфігуровано — користувачу #{user.email_address} НЕ доставлено (алерт ##{alert.id})"
    )
  end
end

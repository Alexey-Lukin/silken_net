# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertNotificationWorker
  include Sidekiq::Job
  # [SIDEKIQ PRO EXPIRES_IN]: При flood черги alerts, сповіщення старші
  # за 5 хвилин втрачають актуальність — патрульні вже побачили новіші.
  sidekiq_options queue: "alerts", retry: 5, expires_in: 5.minutes

  def perform(ews_alert_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless alert

    # 🔴 `cluster` у EwsAlert — `optional: true`, а цей воркер енкʼюїться БЕЗУМОВНО
    # (`after_create_commit :dispatch_notifications!`), і безкластерні алерти реально
    # створюються (AlertDispatchService — ⚠️ НЕ «гілка одинокого дерева»: ⚖️ 2026-07-30
    # одиноке дерево B2C дістає власний кластер із одного, а не NULL). Маршрут до адресатів
    # веде ЛИШЕ через організацію кластера — у дерева `cluster` теж optional, іншого
    # шляху нема. Без цього гарда `cluster.organization` кидав NoMethodError на КОЖНОМУ
    # такому алерті: 5 ретраїв → morgue, тихо й назавжди.
    cluster = alert.cluster
    unless cluster
      Rails.logger.warn "📢 [Notification] Алерт ##{alert.id} без кластера — адресата сповіщень не існує, пропускаю."
      return
    end

    # ДИФЕРЕНЦІЙОВАНА ДОСТАВКА (Smart Routing) — оповіщення відповідальних осіб
    queued = notify_stakeholders(alert, cluster.organization)

    # [ARCH.78] Цей рядок читають ПЕРШИМ під час розбору інциденту, тому він
    # називає рівно те, що воркер зробив: поставив у чергу. Доставку він не
    # спостерігає — її стан живе в логах SingleNotificationWorker.
    Rails.logger.info(
      "[Notification] Тривогу #{alert.alert_type} поставлено в чергу для кластера " \
      "#{cluster.name}: #{queued} сповіщень"
    )
  end

  private

  def notify_stakeholders(alert, organization)
    # А. Email для Організації (Формальна звітність)
    if alert.severity_critical? && organization.billing_email.present?
      AlertMailer.with(alert: alert).critical_notification.deliver_later
    end

    # Б. Оперативні канали (Патруль та Адміни)
    # [A-4 FIX: Wiki 04_02 Audit §14 — Sidekiq Bulk Enqueue]
    # Замість N окремих Redis LPUSH (один per perform_async) — збираємо всі args
    # у масив та відправляємо одним Sidekiq::Client.push_bulk.
    # Це зменшує кількість Redis round-trips з N до 1 при масовому розсиланні.
    # find_each замість each — завантажує батчами, запобігає OOM при 10 000+ лісниках.
    bulk_args = []
    stakeholders = organization.users.where(role: [ :admin, :forester ])

    stakeholders.find_each(batch_size: 500) do |user|
      # SMS лише для критичних ситуацій (Пожежа / Вандалізм)
      bulk_args << [ user.id, alert.id, "sms" ] if alert.severity_critical?

      # Push для всіх рівнів тривог
      bulk_args << [ user.id, alert.id, "push" ]

      # [ARCH.60] Telegram — теж усі рівні: канал opt-in через chat_id, тож
      # адресну вибірку робить сам SingleNotificationWorker (як push із token).
      bulk_args << [ user.id, alert.id, "telegram" ]
    end

    Sidekiq::Client.push_bulk("class" => SingleNotificationWorker, "args" => bulk_args) if bulk_args.any?

    bulk_args.size
  end
end

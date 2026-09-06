# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertNotificationWorker
  include Sidekiq::Job
  # [SIDEKIQ PRO EXPIRES_IN]: При flood черги alerts, сповіщення старші
  # за 5 хвилин втрачають актуальність — патрульні вже побачили новіші.
  # ⚠️ У OSS-редакції (поточній) опція **інертна** — активується лише з Sidekiq Pro
  # (DOC-R.10, `04_02 §11`). Актуальність тут тримає НЕ вона, а семантичний гард
  # `status_active?` у `perform` — див. коментар там.
  sidekiq_options queue: "alerts", retry: 5, expires_in: 5.minutes

  # [E.33] Канали, що доставляються ЧЕРЕЗ `SingleNotificationWorker`. Пошта сюди
  # не входить свідомо: вона має власний шлях (mailer → `billing_email`), одна
  # відправка на алерт незалежно від числа стейкхолдерів.
  # ⚫ `:telegram` знято ⚖️ founder 2026-09-06 [ARCH.60] — лишився сам `:push`, який
  # ратифіковано недоступним до появи мобільного клієнта [ARCH.108]. Отже набір
  # сьогодні порожній ЗА ОГОЛОШЕНИМ ЗАДУМОМ, і саме тому нижче стоїть `info`.
  OPERATIONAL_CHANNELS = %i[push].freeze

  def perform(ews_alert_id)
    alert = EwsAlert.find_by(id: ews_alert_id)
    return unless alert

    # 🔴 [ARCH.59] Стан алерту перевіряється В МОМЕНТ ДОСТАВКИ, а не постановки.
    # `EwsAlert` при резолві не видаляється (`status` = active/resolved/ignored),
    # тож `find_by(id:)` віддає ВИРІШЕНИЙ алерт так само охоче, як живий — і без
    # цього рядка людина отримувала б сповіщення про тривогу, яку вже закрили.
    # Доти вісь трималась на `expires_in: 5.minutes` ↑, який на Sidekiq OSS не
    # робить НІЧОГО (опція Pro; у гемі 8.1.6 рядок `expires_in` не зустрічається
    # взагалі) — тобто захисту не існувало, лише його оголошення. Гард семантичний,
    # а не часовий, СВІДОМО: «застаріле» тут означає «вже не потребує реакції»,
    # і це властивість запису, а не його віку в черзі.
    unless alert.status_active?
      Rails.logger.info "📢 [Notification] Алерт ##{alert.id} уже #{alert.status} — сповіщення не розсилаю."
      return
    end

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
    stakeholders = organization.users.where(role: [ :admin, :forester ])

    # 🔴 [E.33] Найдешевший лімітер — не ставити в чергу канал, ЯКОГО НЕМАЄ.
    # Доти сюди безумовно летіло по джобі `"push"` на кожного стейкхолдера, тоді
    # як `DeliveryChannels.available?(:push)` віддає жорсткий `false` — тобто
    # платформа сама оголошувала транспорт неіснуючим, а черга однаково несла
    # `2 × N` джоб, половина яких була `logger.warn` без жодного I/O. Ціна не
    # косметична: `alerts` дренується STRICT-пріоритетом ПОВНІСТЮ перед
    # `critical`, тож холості джоби вдвічі відсували живі доставки.
    # Предикат тут — ТОЙ САМИЙ One-Home, що питають екран налаштувань і
    # boot-гард пошти; отже дротування FCM вмикає канал без правки цього файлу.
    # ⚠️ Перевірка в `SingleNotificationWorker` лишається backstop-ом, а не
    # дублем: джоба могла лягти в чергу за живого каналу й виконатись уже після
    # зняття токена.
    live_channels = OPERATIONAL_CHANNELS.select { |channel| Notifications::DeliveryChannels.available?(channel) }

    if live_channels.empty?
      # Голос НУЛЮ лишається — «оперативних каналів немає» ⊥ «стейкхолдерів
      # немає» досі два різні світи, і мовчання злило б їх у один.
      # 🔴 Але РІВЕНЬ знижено `warn` → `info` ⚖️ 2026-09-06 разом зі зняттям
      # Telegram: доти порожній набір був АНОМАЛІЄЮ (канал жив, зник токен),
      # тепер це ОГОЛОШЕНИЙ СТАН — у наборі сам `:push`, ратифіковано недоступний.
      # Warn на кожен алерт зробив би з сигналу шум, а тривога, що звучить
      # завжди, не звучить ніколи. Носій стану — не цей рядок, а нога дротування
      # FCM/пошти в `00_07` ARCH.60.
      Rails.logger.info(
        "[Notification] Оперативних каналів немає ЗА ЗАДУМОМ (#{OPERATIONAL_CHANNELS.join('/')}; push — до мобільного клієнта, Telegram знято 09-06) — " \
        "#{stakeholders.count} стейкхолдерів бачать тривогу ##{alert.id} лише на дашборді; critical — поштою"
      )
      return 0
    end

    bulk_args = []
    stakeholders.find_each(batch_size: 500) do |user|
      # [ARCH.60] Канал opt-in через chat_id/token, тож адресну вибірку робить
      # сам SingleNotificationWorker. SMS-каналу немає: відкинуто присудом
      # [ARCH.78, 2026-08-20]; ⚫ Telegram знято ⚖️ 2026-09-06 — сценарій покриває
      # пошта (critical ↑) плюс дашборд, доки не задротовано FCM [ARCH.108].
      live_channels.each { |channel| bulk_args << [ user.id, alert.id, channel.to_s ] }
    end

    Sidekiq::Client.push_bulk("class" => SingleNotificationWorker, "args" => bulk_args) if bulk_args.any?

    bulk_args.size
  end
end

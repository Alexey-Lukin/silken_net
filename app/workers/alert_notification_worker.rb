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
    ActionCable.server.broadcast("org_#{alert.cluster.organization_id}_alerts", payload)
  rescue StandardError => e
    Rails.logger.error "🛑 [ActionCable] WebSocket Error: #{e.message}"
  end

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
    end

    Sidekiq::Client.push_bulk("class" => SingleNotificationWorker, "args" => bulk_args) if bulk_args.any?
  end
end

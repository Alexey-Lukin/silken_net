# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AuditLogWorker
  include Sidekiq::Job
  # Аудит-логування — фонова операція, що не потребує оперативного виконання.
  # Черга low відповідає пріоритету нижчестоящого FilecoinArchiveWorker.
  sidekiq_options queue: "low", retry: 3

  # [INF.22 крок 11] Outbox-маркер: archive=true (money/MRV audit) — ЄДИНИЙ шлях, що архівує
  # на IPFS. Ставимо archive_requested_at атомарно з create → FilecoinReconcileWorker підбере
  # лог навіть якщо perform_async нижче загубиться (Redis-down у вікні між create! і enqueue).
  # archive=false [ARCH.57] = chain-only привілейовані дії (ключі/ролі/актуатори — security-
  # метадані НЕ на публічний IPFS); прямий AuditLog.create! (factory/console) — теж поза periметром.
  def perform(attrs, archive = true)
    attrs = attrs.deep_stringify_keys
    attrs = attrs.merge("archive_requested_at" => Time.current) if archive

    log = AuditLog.create!(attrs)
    FilecoinArchiveWorker.perform_async(log.id) if archive
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "🛑 [AuditLog] Невалідний запис: #{e.message}"
  end
end

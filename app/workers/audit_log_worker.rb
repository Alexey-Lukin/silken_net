# frozen_string_literal: true

class AuditLogWorker
  include Sidekiq::Job
  # Аудит-логування — фонова операція, що не потребує оперативного виконання.
  # Черга low відповідає пріоритету нижчестоящого FilecoinArchiveWorker.
  sidekiq_options queue: "low", retry: 3

  def perform(attrs)
    # [INF.22 крок 11] Outbox-маркер: цей шлях (money/MRV audit) — ЄДИНИЙ, що архівує на
    # IPFS. Ставимо archive_requested_at атомарно з create → FilecoinReconcileWorker підбере
    # лог навіть якщо perform_async нижче загубиться (Redis-down у вікні між create! і enqueue).
    # Прямий AuditLog.create! (codex/factory) маркер НЕ ставить → навмисно не архівується.
    log = AuditLog.create!(attrs.deep_stringify_keys.merge("archive_requested_at" => Time.current))
    FilecoinArchiveWorker.perform_async(log.id)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "🛑 [AuditLog] Невалідний запис: #{e.message}"
  end
end

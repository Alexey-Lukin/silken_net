# frozen_string_literal: true

class AuditLogWorker
  include Sidekiq::Job
  # Аудит-логування — фонова операція, що не потребує оперативного виконання.
  # Черга low відповідає пріоритету нижчестоящого FilecoinArchiveWorker.
  sidekiq_options queue: "low", retry: 3

  def perform(attrs)
    log = AuditLog.create!(attrs)
    FilecoinArchiveWorker.perform_async(log.id)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "🛑 [AuditLog] Невалідний запис: #{e.message}"
  end
end

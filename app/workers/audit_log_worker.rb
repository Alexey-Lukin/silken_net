# frozen_string_literal: true

class AuditLogWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(attrs)
    log = AuditLog.create!(attrs)
    FilecoinArchiveWorker.perform_async(log.id)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "🛑 [AuditLog] Невалідний запис: #{e.message}"
  end
end

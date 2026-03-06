# frozen_string_literal: true

class AuditLogWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(attrs)
    AuditLog.create!(attrs)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "🛑 [AuditLog] Невалідний запис: #{e.message}"
  end
end

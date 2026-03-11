# frozen_string_literal: true

class FilecoinArchiveWorker
  include Sidekiq::Job
  sidekiq_options queue: "low", retry: 5

  def perform(audit_log_id)
    audit_log = AuditLog.find(audit_log_id)

    Filecoin::ArchiveService.new(audit_log).archive!
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "📦 [Filecoin] AuditLog ##{audit_log_id} not found, skipping"
  end
end

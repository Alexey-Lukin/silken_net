# frozen_string_literal: true

class FilecoinArchiveWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "low", retry: 5

  def perform(audit_log_id)
    audit_log = AuditLog.find(audit_log_id)

    with_web3_error_handling("Filecoin", "AuditLog ##{audit_log_id}") do
      Filecoin::ArchiveService.new(audit_log).archive!
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "📦 [Filecoin] AuditLog ##{audit_log_id} not found, skipping"
  end
end

# frozen_string_literal: true

class FilecoinArchiveWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "low", retry: 5

  # [INF.22 крок 11] Detect-половина: без цього hook вичерпаний archive (Pinata down 5×)
  # тихо осідав у Dead Set → ipfs_cid NULL назавжди, а sweep (лише :archived) його НІКОЛИ
  # не бачив (self-masking, дзеркало ARCH.64/65). Тепер вичерпання інкрементить attributable
  # лічильник; FilecoinReconcileWorker (:48) підбере лог за outbox-маркером і re-enqueue'їть.
  sidekiq_retries_exhausted do |job, exception|
    audit_log_id = job["args"].first
    Rails.logger.error "🛑 [Filecoin] ArchiveWorker вичерпав retry для AuditLog ##{audit_log_id} — " \
                       "архів осів у Dead Set, ipfs_cid лишається NULL (reconcile re-pin'ить): #{exception.message}"
    SilkenNet::Metrics::FILECOIN_ARCHIVE_EXHAUSTED_TOTAL.increment
  end

  def perform(audit_log_id)
    audit_log = AuditLog.find(audit_log_id)

    with_web3_error_handling("Filecoin", "AuditLog ##{audit_log_id}") do
      Filecoin::ArchiveService.new(audit_log).archive!
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "📦 [Filecoin] AuditLog ##{audit_log_id} not found, skipping"
  end
end

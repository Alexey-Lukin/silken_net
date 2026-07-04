# frozen_string_literal: true

# [E.60] Озброєння content-CID guard: Filecoin::VerificationService був
# збудований, але мав 0 prod-callerів (FilecoinArchiveWorker кличе лише
# archive!). Щоденний sweep звіряє архіви з IPFS двома вибірками:
#   (а) свіжо-заархівовані (24h-вікно) — кожен архів звірено хоч раз;
#   (б) випадкова вибірка старших — ex-post підміна можлива БУДЬ-КОЛИ,
#       тож самі лише свіжі не покривають threat-model E.60.
# Mismatch → ERROR-лог + silkennet_filecoin_verification_failures_total
# (Grafana-алерт), БЕЗ raise: integrity-fail не «лікується» retry, а
# gateway-флейк не має валити весь sweep.
class FilecoinVerificationSweepWorker
  include Sidekiq::Job
  sidekiq_options queue: "low", retry: 2

  FRESH_WINDOW = 24.hours
  FRESH_LIMIT = 200
  # [transitional] ORDER BY RANDOM() = O(n) по archived-набору; стеля відома,
  # апгрейд-шлях = TABLESAMPLE SYSTEM при мільйонах архівів (ARCH.52-клас).
  SAMPLE_SIZE = 25

  def perform
    stats = { verified: 0, failed: 0, unreachable: 0 }

    (fresh_batch + random_sample).uniq.each do |audit_log|
      verify_one(audit_log, stats)
    end

    Rails.logger.info "🔍 [E.60] Filecoin sweep: #{stats[:verified]} verified, " \
                      "#{stats[:failed]} FAILED, #{stats[:unreachable]} unreachable."
  end

  private

  def fresh_batch
    AuditLog.archived.where(updated_at: FRESH_WINDOW.ago..).limit(FRESH_LIMIT).to_a
  end

  def random_sample
    AuditLog.archived.where(updated_at: ...FRESH_WINDOW.ago)
            .order(Arel.sql("RANDOM()")).limit(SAMPLE_SIZE).to_a
  end

  def verify_one(audit_log, stats)
    result = Filecoin::VerificationService.new(audit_log).verify!

    if result[:verified]
      stats[:verified] += 1
    else
      stats[:failed] += 1
      reason = result[:reason] || "chain_hash_mismatch"
      Rails.logger.error "🛑 [E.60] INTEGRITY FAIL AuditLog ##{audit_log.id} (#{reason}): #{result.inspect}"
      SilkenNet::Metrics::FILECOIN_VERIFICATION_FAILURES_TOTAL.increment(labels: { reason: reason })
    end
  rescue Web3::HttpClient::RequestError => e
    # Gateway-флейк ≠ integrity-fail: не рахуємо у failures, sweep триває.
    stats[:unreachable] += 1
    Rails.logger.warn "🌫️ [E.60] IPFS gateway unreachable for AuditLog ##{audit_log.id}: #{e.message}"
  end
end

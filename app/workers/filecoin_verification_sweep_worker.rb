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

  # [E.60 Фаза 1б] Семпл стемпнутих листів: merkle_leaf пишеться raw-SQL'ем
  # (pin-воркер, AR-колбеки не стріляють) → seal-guard моделі його не бачить;
  # ця нога — друга половина пари (guard = AR-шлях, sweeper = raw-шлях).
  # Вибірка через partial index (merkle_leaf, created_at) WHERE NOT NULL по
  # свіжому вікну — БЕЗ ORDER BY RANDOM() (партиційована таблиця = full-scan).
  LEAF_SAMPLE_WINDOW = 7.days
  LEAF_SAMPLE_SIZE = 50

  def perform
    stats = { verified: 0, failed: 0, unreachable: 0, leaf_ok: 0, leaf_drift: 0 }

    (fresh_batch + random_sample).uniq.each do |audit_log|
      verify_one(audit_log, stats)
    end

    leaf_stamp_sample.each { |log| verify_leaf_stamp(log, stats) }

    Rails.logger.info "🔍 [E.60] Filecoin sweep: #{stats[:verified]} verified, " \
                      "#{stats[:failed]} FAILED, #{stats[:unreachable]} unreachable; " \
                      "leaf-стемпи: #{stats[:leaf_ok]} ok, #{stats[:leaf_drift]} DRIFT."
  end

  private

  def fresh_batch
    AuditLog.archived.where(updated_at: FRESH_WINDOW.ago..).limit(FRESH_LIMIT).to_a
  end

  def random_sample
    AuditLog.archived.where(updated_at: ...FRESH_WINDOW.ago)
            .order(Arel.sql("RANDOM()")).limit(SAMPLE_SIZE).to_a
  end

  def leaf_stamp_sample
    TelemetryLog.where.not(merkle_leaf: nil)
                .where(created_at: LEAF_SAMPLE_WINDOW.ago..)
                .limit(LEAF_SAMPLE_SIZE).to_a
  end

  # Перерахований CID ≠ стемп = мутація payload'а повз AR-guard (raw-SQL) АБО
  # битий стемп — integrity-сигнал того ж класу, що content-CID mismatch.
  def verify_leaf_stamp(log, stats)
    if Mrv::TelemetryLeaf.cid_for(log) == log.merkle_leaf
      stats[:leaf_ok] += 1
    else
      stats[:leaf_drift] += 1
      Rails.logger.error "🛑 [E.60] LEAF-STAMP DRIFT TelemetryLog ##{log.id}: перерахований CID ≠ merkle_leaf."
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "leaf_stamp_drift" })
    end
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

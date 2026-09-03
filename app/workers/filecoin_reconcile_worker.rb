# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 📦 FILECOIN ARCHIVE OUTBOX RECONCILE (INF.22 крок 11 — repair-половина)
# = ===================================================================
# FilecoinArchiveWorker (retry:5) архівує AuditLog на IPFS/Filecoin, але при вичерпанні
# retry (Pinata down) архів осідав у Dead Set → ipfs_cid NULL назавжди, а
# FilecoinVerificationSweepWorker (дивиться лише :archived) цього НІКОЛИ не бачив
# (self-masking, дзеркало ARCH.64/65 — див. FilecoinArchiveWorker exhausted-hook = detect).
# Цей sweep = repair-половина: дренажить outbox-marked money/MRV-логи, застряглі без
# ipfs_cid, назад у archive.
#
# [SCOPE — OUTBOX, не голий not_archived]: лише `AuditLog.pending_archive` = логи з
# виставленим `archive_requested_at` (money/MRV-шлях через AuditLogWorker). Factory/console
# прямий `create!` маркер НЕ ставлять → навмисно поза периметром (без крихкої
# auditable_type-евристики; over-pinning factory/console = Pinata quota-waste + security
# over-exposure factory-provenance на публічний IPFS).
#
# [MONEY-SAFE / ідемпотентно, БЕЗ reload-guard]: на відміну від CeloRewardReconcileWorker
# (пише :manual_review → потребує reload-guard), тут нічого не пишемо самі — лише re-enqueue
# вже-ідемпотентного FilecoinArchiveWorker (`archive!` early-returns на `ipfs_cid.present?`).
# Гонка з живим archive'ом безпечна: найгірше — 1 зайвий Pinata-pin (payload несе `archived_at`
# → інший IpfsHash, АЛЕ content-CID guard E.60 виключає `archived_at` з `CONTENT_DIGEST_KEYS`,
# тож verify не ламається), НЕ money-рух, НЕ подвійний chain_hash.
class FilecoinReconcileWorker
  include Sidekiq::Job

  # `unique_for` = Enterprise-шим (зараз no-op без sidekiq-ent); overlap безпечний і так —
  # re-enqueue ідемпотентний. `low` = найнижчий пріоритет (audit-архів не час-критичний).
  sidekiq_options queue: "low", retry: 3, unique_for: 23.hours

  # Молодші за це ще в первинному FilecoinArchiveWorker retry-циклі (retry:5 backoff) — не
  # чіпаємо. `low` = найнижчий пріоритет strict-drain (ARCH.52) → щедріше за Celo(30хв)/Hadron(1г);
  # калібрувати проти silkennet_sidekiq_queue_latency_seconds{queue="low"}.
  STALE_THRESHOLD = 2.hours

  # Нижня межа скану = budget-starvation guard (НЕ partition-prune — audit_logs не
  # партиційована): без неї permanently-stuck найстаріший рядок (напр. тижневий Pinata-збій)
  # вічно зʼїдав би весь BATCH_LIMIT oldest-first і блокував НОВІШІ відновлювані логи. Щедра
  # (30д — MRV/compliance горизонт; немає manual_review-ескалації як запобіжника). Хвіст,
  # старший за LOOKBACK, лишається видимим у depth-gauge (нижче), просто не re-enqueue'иться.
  LOOKBACK = 30.days

  # Стеля re-enqueue за прогін — backlog дренажиться послідовними cron'ами, не flood'ом проти
  # щойно-оживаючого Pinata (дзеркало Celo/Hadron). [known-ceiling] При багатоденному Pinata-
  # outage кожен re-enqueue знову вичерпує archive-retry:5 → Dead Set; DAILY-cadence (не hourly)
  # тримає притік ≤BATCH_LIMIT/добу. Severity-inversion (P1 money-deadset alert від non-money
  # archive-джоба) + scale-eviction money-трупів = pre-existing (global sidekiq_dead_set_size);
  # реальний фікс (Pinata health-probe gate / label-filter) відкладено до live-трафіку.
  BATCH_LIMIT = 500

  def perform
    # [ARCH.118-клас] Несконфігурована нога: ре-арм без ключа лише спалює слоти й Sentry.
    # Рядки лишаються видимими в `silkennet_filecoin_unarchived_depth` — тиша тут ГОЛОСУ не
    # забирає, бо гейдж і є каналом «скільки чекає».
    unless Filecoin::ArchiveService.configured?
      Rails.logger.info "📦 [Filecoin] Re-arm пропущено — нога не сконфігурована (FILECOIN_API_KEY)."
      return
    end

    ids = AuditLog.pending_archive
                  .where(archive_requested_at: LOOKBACK.ago..STALE_THRESHOLD.ago)
                  .order(:archive_requested_at)
                  .limit(BATCH_LIMIT)
                  .pluck(:id)

    ids.each { |id| FilecoinArchiveWorker.perform_async(id) }
    SilkenNet::Metrics::FILECOIN_REPIN_TOTAL.increment(by: ids.size) if ids.any?

    if ids.any?
      Rails.logger.warn "📦 [INF.22] Re-enqueued #{ids.size} застряглих archive-requested AuditLog'ів → " \
                        "FilecoinArchiveWorker (Pinata-exhaustion recovery)."
    end

    reconcile_archive_batches
  end

  private

  # [E.60 Фаза 1б] Друга нога — телеметрія-архів-батчі: первинний enqueue іде
  # одразу при створенні batch-row (Mrv::TelemetryArchiveBatchService), тут —
  # backstop на crash/pin-вичерпання (pending) + repair-нога (build_failed →
  # пізній rebuild у воркері). Ідемпотентно: термінали CAS-гардовані в моделі,
  # superseded/retention_expired/pinned/mismatch поза скоупом .reconcilable.
  # ⚠️ Daily-cadence: поріг STALE_THRESHOLD моделі (2h) = фільтр віку, не SLA —
  # реальна затримка backstop'а ≤24h (первинний enqueue тримає штатний шлях швидким).
  def reconcile_archive_batches
    batch_ids = TelemetryArchiveBatch.reconcilable
                                     .order(:updated_at)
                                     .limit(BATCH_LIMIT)
                                     .pluck(:id)
    return if batch_ids.empty?

    batch_ids.each { |id| TelemetryArchiveBatchWorker.perform_async(id) }
    Rails.logger.warn "📦 [E.60] Re-enqueued #{batch_ids.size} застряглих archive-батчів → " \
                      "TelemetryArchiveBatchWorker (pin/repair backstop)."
  end
end

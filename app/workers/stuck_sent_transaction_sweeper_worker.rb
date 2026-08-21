# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🧹 STUCK-:sent SWEEPER (ARCH.55 — The Mempool Limbo Re-arm)
# = ===================================================================
# Money-path recovery net for a class NO earlier audit caught: a container
# OOM / eviction DURING BlockchainConfirmationWorker polling leaves a tx
# stranded in :sent FOREVER — pending-discovery (mint_batch_collector) scans
# only :pending/:processing, and MintingRollbackService fires only from
# retries_exhausted, never from a mid-poll crash. The forester's growth_points
# stay in locked_balance (not double-spend — stranded).
#
# Fix: periodically re-enqueue BlockchainConfirmationWorker for any tx that has
# been :sent longer than STUCK_THRESHOLD. It resolves →:confirmed / :failed
# (which now releases locked_points, M2) exactly as the original poll would have.
#
# Covers the rails that actually persist a `BlockchainTransaction` row: mint /
# burn / insurance. ⚠️ NOT puro — its hash lives on `MaintenanceRecord`, never in
# `blockchain_transactions`, and it has its OWN lifecycle+poller
# (PuroEarthConfirmationWorker) — the THIRD form of that lifecycle; its
# stuck-:sent sweep is deliberately deferred until path activation
# (`ORACLE_PURO_PRIVATE_KEY`) and lives at `00_07` ARCH.66.
# Celo has its own CeloConfirmationWorker; Solana/anchor reconcile via their own
# crons — out of scope here (see 00_07 ARCH.55).
#
# [sent_at, NOT created_at] The threshold keys on broadcast time (sent_at),
# because a reset-to-pending tx keeps an OLD created_at (ARCH.52 trap) — a
# created_at window would MISS a genuinely-stuck tx whose pending wait was long.
# created_at is still passed to ConfirmationWorker for partition-pruning.
#
# [Idempotent re-arm] A concurrent live poller is harmless: AASM `confirm` fires
# once, a duplicate hits AASM::InvalidTransition → Sidekiq retry → retries_exhausted
# finds no :sent row → no-op (wasteful, not unsafe). With Sidekiq Enterprise the
# ConfirmationWorker `unique_for` dedups the duplicate outright.
class StuckSentTransactionSweeperWorker
  include Sidekiq::Job

  # web3 (recovery, not time-critical intake). Own unique_for guards against two
  # sweeper crons overlapping (no-op without Enterprise, real with it).
  sidekiq_options queue: "web3", retry: 3, unique_for: 9.minutes

  # A tx :sent longer than this had its confirmation poller die mid-flight
  # (10 retries ≈ 15-20 min). Anything younger may still be a live poller.
  STUCK_THRESHOLD = 15.minutes

  # Safety cap on re-arms per run — a backlog is drained across successive crons
  # rather than enqueuing an unbounded flood in one pass.
  BATCH_LIMIT = 500

  def perform
    cutoff = STUCK_THRESHOLD.ago

    # [P2-3] ТІЛЬКИ EVM: BlockchainConfirmationWorker полить Polygon RPC. Solana/Celo теж ставлять
    # `sent_at` (mark_as_sent!) + мають ВЛАСНІ reconcile-крони (solana_batch_payout / CeloConfirmationWorker)
    # → без цього фільтра Solana-payout летів би у Polygon-поллер → 15-20хв wasted RPC + передчасний
    # manual_review (Polygon не має Solana-signature).
    stuck = BlockchainTransaction.status_sent
                                 .where(blockchain_network: "evm")
                                 .where("sent_at < ?", cutoff)
                                 .order(:created_at)
                                 .limit(BATCH_LIMIT)
                                 .to_a

    # Dedup by tx_hash (a batchMint shares one hash across N rows) → one
    # ConfirmationWorker per hash, with the EARLIEST created_at so the worker's
    # `created_at >= earliest - 1h` scope covers the whole batch (mirror ARCH.52).
    re_armed = 0
    stuck.group_by(&:tx_hash).each do |tx_hash, rows|
      next if tx_hash.blank?

      earliest = rows.min_by(&:created_at).created_at
      BlockchainConfirmationWorker.perform_async(tx_hash, earliest.iso8601)
      re_armed += 1
    end

    if re_armed.positive?
      Rails.logger.warn "🧹 [ARCH.55] Re-armed #{re_armed} stuck-:sent tx_hash(es) " \
                        "(sent_at older than #{STUCK_THRESHOLD.inspect}) for confirmation."
    end

    escalate_stuck_processing!(cutoff)
  end

  private

  # [ARCH.45 :processing-orphan] non-StandardError крах між `transact("mint")` і
  # `mark_as_sent` лишає tx у :processing НАЗАВЖДИ: tx_hash невідомий (on-chain
  # доля ambiguous — мінт МІГ landed), жоден mint-шлях :processing не чіпає
  # (double-mint неможливий), але баланс форестера висить у locked. Політика
  # ARCH.48/M6: ambiguous → :manual_review (людська звірка на Polygonscan),
  # НІКОЛИ blind re-mint. Ключ = updated_at (state-перехід бампає; created_at
  # труїть reset-to-pending — ARCH.52 trap). Живий batch тримає :processing
  # секунди — 15min відсіює лише трупи.
  def escalate_stuck_processing!(cutoff)
    orphans = BlockchainTransaction.status_processing
                                   .where(updated_at: ...cutoff)
                                   .order(:created_at)
                                   .limit(BATCH_LIMIT)
                                   .to_a
    return if orphans.empty?

    escalated = 0
    orphans.each do |tx|
      # Guard пере-читанням: між SELECT'ом і цим рядком живий поллер міг довершити
      # mark_as_sent! — stale in-memory :processing перетер би свіжий :sent
      # (escalate дозволяє sent→manual_review). Мілісекундний залишок гонки
      # деградує лише в зайвий manual_review (безпечний напрямок), не в double-act.
      # [S6.16] Через One-Home, не голим `.reload`: той б'є по самому PK і сканує ВСІ
      # партиції — до BATCH_LIMIT разів за прогін, хоч `created_at` уже в пам'яті
      # з SELECT'а вище. Прецедент форми — CeloRewardReconcileWorker.
      fresh = BlockchainTransaction.find_with_partition_pruning(tx.id, tx.created_at)
      next unless fresh.status_processing?

      fresh.escalate_to_review!("[ARCH.45] :processing-orphan >#{STUCK_THRESHOLD.inspect} — крах між transact і mark_as_sent; мінт міг landed → звір на Polygonscan, НЕ re-mint.")
      escalated += 1
    end

    # Лічимо ФАКТИЧНІ ескалації, не розмір вибірки: guard вище пропускає ті, що
    # їх щойно довершив живий поллер, тож `orphans.size` звітував би про дію,
    # якої не сталося.
    #
    # 🔴 [PERF.1] Але НУЛЬ ескалацій ≠ нічого не сталося: доти `return unless positive?`
    # робив свіпер ПОВНІСТЮ німим у випадку, коли гард пропустив усю вибірку — тобто
    # рівно тоді, коли до BATCH_LIMIT транзакцій висіли в `:processing` понад поріг і
    # всі довершились у мілісекундну щілину. Оператор не бачив ані «є N підозрілих»,
    # ані «усі виявились живими», і не-дія знову не свідчила про себе. Рівень `info`,
    # а не `warn`, свідомо: це спостереження про здоровий тракт, не інцидент.
    if escalated.zero?
      Rails.logger.info "🧹 [ARCH.45] Розглянуто #{orphans.size} :processing-орфан(ів), " \
                        "ескальовано 0 — усіх довершив живий поллер між SELECT'ом і пере-читанням."
      return
    end

    Rails.logger.warn "🧹 [ARCH.45] Escalated #{escalated} stuck-:processing orphan(s) to :manual_review."
  end
end

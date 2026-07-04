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
# Covers ALL rails on the shared BlockchainConfirmationWorker (mint / burn /
# insurance / puro). Celo has its own CeloConfirmationWorker; Solana/anchor
# reconcile via their own crons — out of scope here (see 00_07 ARCH.55).
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

    stuck = BlockchainTransaction.status_sent
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
  end
end

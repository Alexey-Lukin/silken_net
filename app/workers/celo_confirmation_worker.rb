# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.50] Celo-aware reconcile for a `:sent` cUSD reward.
# `BlockchainConfirmationWorker` is hardcoded to the Polygon RPC, so it cannot
# poll a Celo transaction — a reward needs its own Celo-RPC poller. Resolves the
# `:sent` intent on-chain (reuses the shared `Web3::EvmReceiptClassifier`):
#   :confirmed → confirm!  (org received the cUSD; dedup keeps blocking a re-pay)
#   :reverted  → fail!     (cUSD never moved → dedup excludes :failed → next cycle re-pays)
#   :pending   → raise → Sidekiq retry (re-poll on the next orbit)
# This is NOT `MintingRollbackService#perform_safe_rollback` — a reward has no
# `locked_balance` to release (it is a transfer, not a mint-lock).
class CeloConfirmationWorker
  include ApplicationWeb3Worker
  # 10 retries ≈ 15-20 хв polling; unique_for запобігає конкурентному поллінгу того ж tx.
  sidekiq_options queue: "web3", retry: 10, unique_for: 10.minutes

  sidekiq_retries_exhausted do |msg, _ex|
    tx_id, created_at_iso = msg["args"]
    tx = BlockchainTransaction.find_with_partition_pruning(tx_id, created_at_iso)
    next unless tx.status_sent?

    Rails.logger.warn "⚠️ [Celo Confirm] Polling вичерпано для винагороди ##{tx_id} — ескалація до manual_review."
    tx.escalate_to_review!("Celo reward confirmation polling exhausted — звірити на Celo explorer перед будь-яким re-pay")
  end

  def perform(tx_id, created_at_iso = nil)
    # find_with_partition_pruning робить `first!` → RecordNotFound (нижче rescue), НЕ nil:
    # якщо ми тут, tx гарантовано присутній (тому `.`, не `&.`).
    tx = BlockchainTransaction.find_with_partition_pruning(tx_id, created_at_iso)
    return Rails.logger.info "🌿 [Celo Confirm] tx ##{tx_id} вже :#{tx.status} — пропускаємо." unless tx.status_sent?

    receipt = within_rpc_limit do
      # ⚖️ [2026-08-31] `DEFAULT_RPC_URL` знято — без `fallback:` це `ENV.fetch`, тобто
      # fail-loud на незаданій змінній. Підстава — у знятої константи, `CommunityRewardService`.
      client = Web3::RpcConnectionPool.client_for(
        "CELO_RPC_URL",
        fallback_env_keys: Celo::CommunityRewardService::RPC_FALLBACK_ENV_KEYS
      )
      client.eth_get_transaction_receipt(tx.tx_hash)
    end

    case Web3::EvmReceiptClassifier.classify(receipt)
    when :confirmed
      tx.confirm!
      Rails.logger.info "🌿 [Celo Confirm] Винагороду ##{tx_id} підтверджено on-chain. cUSD доставлено."
    when :reverted
      # cUSD НЕ перемістився → :failed (dedup виключає :failed) → наступний цикл re-pay-ить.
      tx.fail!("Celo cUSD transfer reverted on-chain — re-payable")
      Rails.logger.warn "↩️ [Celo Confirm] Винагорода ##{tx_id} reverted → :failed (re-payable наступного циклу)."
    else
      # :pending — ще в мемпулі → помилка → Sidekiq retry (re-poll).
      raise "⏳ Celo reward ##{tx_id} ще не підтверджено мережею — retry на наступному прольоті."
    end
  rescue ActiveRecord::RecordNotFound
    # Reward tx видалено між enqueue і perform → no-op (нічого звіряти).
    Rails.logger.info "🌿 [Celo Confirm] reward tx ##{tx_id} не знайдено — no-op."
  end
end

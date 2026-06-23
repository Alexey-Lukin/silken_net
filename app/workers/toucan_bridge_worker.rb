# frozen_string_literal: true

class ToucanBridgeWorker
  include ApplicationWeb3Worker
  # [E.66] retry БЕЗ sidekiq_retries_exhausted — остаточний крах лишає tx pending + кошти заморожені; симетричний rollback перед активацією → 00_07 E.66.
  sidekiq_options queue: "web3_critical", retry: 5

  # [COMPOSITE PK]: blockchain_transactions партиціоновано по created_at.
  # Передача created_at_iso дозволяє PostgreSQL пропустити непотрібні партиції.
  # Без created_at_iso — fallback до повного сканування (зворотна сумісність).
  def perform(blockchain_transaction_id, created_at_iso = nil)
    tx = find_blockchain_tx_with_pruning(blockchain_transaction_id, created_at_iso, log_prefix: "[Toucan]")
    return unless tx

    # [P1 ІДЕМПОТЕНТНІСТЬ]: Якщо TX вже відправлено (наприклад, попередній ретрай виконав
    # deposit, але впав на wallet update), виходимо без повторного виклику — Double-Spend захист.
    return Rails.logger.warn "⚠️ [Toucan] TX ##{tx.id} вже оброблено. Пропускаємо." if tx.status_sent? || tx.status_confirmed?

    with_web3_error_handling("Polygon", "Toucan Bridge TX ##{tx.id}") do
      tx_hash = Toucan::BridgeService.call(blockchain_transaction_id, created_at_iso)

      tx.mark_as_sent!(tx_hash)

      tx.wallet.with_lock do
        tx.wallet.decrement!(:locked_balance, tx.locked_points)
        tx.wallet.increment!(:toucan_bridged_balance, tx.locked_points)
      end

      BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)

      Rails.logger.info "🌉 [Toucan] Bridge TX ##{tx.id} відправлено: #{tx_hash}"
    end
  end
end

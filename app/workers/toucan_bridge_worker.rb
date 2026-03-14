# frozen_string_literal: true

class ToucanBridgeWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_critical", retry: 5

  def perform(blockchain_transaction_id)
    tx = BlockchainTransaction.find(blockchain_transaction_id)

    with_web3_error_handling("Polygon", "Toucan Bridge TX ##{tx.id}") do
      tx_hash = Toucan::BridgeService.call(blockchain_transaction_id)

      tx.mark_as_sent!(tx_hash)

      tx.wallet.with_lock do
        tx.wallet.decrement!(:locked_balance, tx.locked_points)
        tx.wallet.increment!(:toucan_bridged_balance, tx.locked_points)
      end

      BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)

      Rails.logger.info "🌉 [Toucan] Bridge TX ##{tx.id} відправлено: #{tx_hash}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Toucan] BlockchainTransaction ##{blockchain_transaction_id} не знайдено."
  end
end

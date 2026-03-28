# frozen_string_literal: true

# P0 Fix: BlockchainConfirmationWorker queries BlockchainTransaction.where(tx_hash: tx_hash)
# on every polling cycle. Without an index this is a full sequential scan — catastrophic
# at billions-of-rows planetary scale (1B trees × monthly SCC minting).
#
# CONCURRENTLY allows zero-downtime index creation: no table-level lock, existing reads/writes
# are unaffected. The tradeoff is that CONCURRENTLY cannot run inside a transaction.
class AddTxHashIndexToBlockchainTransactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :blockchain_transactions, :tx_hash,
              name: "index_blockchain_transactions_on_tx_hash",
              algorithm: :concurrently,
              where: "tx_hash IS NOT NULL"
  end
end

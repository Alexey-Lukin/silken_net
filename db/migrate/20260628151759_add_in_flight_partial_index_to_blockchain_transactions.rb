# frozen_string_literal: true

# [ARCH.52] Partial index over the in-flight (un-settled) BlockchainTransaction set.
#
# Money-path discovery queries scan the in-flight статуси across the WHOLE created_at
# history with no standalone status index (only composite (wallet_id, status)):
#   - Treasury::MintBatchCollectorService#fetch_pending_transactions  (status: :pending)
#   - MintCarbonCoinWorker#process_pending_transactions               (status_pending)
#   - MintCarbonCoinWorker.sidekiq_retries_exhausted                  (status IN pending,processing)
#
# These CANNOT be created_at-bounded: reset-to-pending (MintCarbonCoinWorker raw update_all
# on RPC-error) keeps the OLD created_at, and MAX_PENDING_AGE_MINUTES makes старі pending
# *urgent* — a lower bound would orphan stranded funds. The safe prune is a PARTIAL index:
# pending+processing = крихітна частка all-time рядків (більшість осідають confirmed/failed),
# тож індекс лишається малим, а planetary-scale full-history scan стає index range-scan.
# status enum: pending=0, processing=1 (BlockchainTransaction#status).
class AddInFlightPartialIndexToBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    # Партиційований parent → Postgres НЕ підтримує CREATE INDEX CONCURRENTLY (рекурсує у
    # партиції однією транзакцією). Pre-launch: партиції порожні → recursive create миттєвий,
    # lock нешкідливий. safety_assured документує свідоме non-concurrent на порожній таблиці.
    safety_assured do
      add_index :blockchain_transactions, [ :status, :created_at ],
                where: "status IN (0, 1)",
                name: "index_blockchain_transactions_in_flight"
    end
  end
end

# frozen_string_literal: true

# Додаємо поля для:
# 1. Метрик газу (gas_price, gas_used, cumulative_gas_cost) — фінансова звітність Series C
# 2. Номер блоку (block_number) — захист від реорганізацій Polygon
# 3. Nonce — ідемпотентність та захист від подвійного мінтингу
# 4. Часові мітки станів (sent_at, confirmed_at) — аналіз латентності мережі
class AddGasMetricsAndBlockDepthToBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    change_table :blockchain_transactions, bulk: true do |t|
      # --- Фінансова звітність (Gas Metrics) ---
      t.decimal :gas_price, comment: "Gas price in wei at time of transaction"
      t.decimal :gas_used, comment: "Gas units consumed by the transaction"
      t.decimal :cumulative_gas_cost, comment: "Total gas cost in MATIC/POL (gas_price * gas_used)"

      # --- Захист від реорганізацій (Block Depth) ---
      t.bigint :block_number, comment: "Block number where transaction was included"

      # --- Ідемпотентність (EVM Nonce) ---
      t.integer :nonce, comment: "EVM transaction nonce for idempotency"

      # --- Часові мітки станів (Latency Analysis) ---
      t.datetime :sent_at, comment: "Timestamp when transaction was broadcast to mempool"
      t.datetime :confirmed_at, comment: "Timestamp when transaction was confirmed on-chain"
    end

    add_index :blockchain_transactions, :block_number
    add_index :blockchain_transactions, :confirmed_at
  end
end

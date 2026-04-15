# frozen_string_literal: true

# [BLOCKER-2] Створення таблиці ethereum_anchors для персистентності state_root та tx_hash.
# Забезпечує аудит-трейл L1 anchoring операцій для регуляторного compliance
# та можливість відтворення state_root зовнішнім аудитором (BLOCKER-6).
class CreateEthereumAnchors < ActiveRecord::Migration[8.1]
  def change
    create_table :ethereum_anchors do |t|
      # State root — 64-char SHA-256 hex string
      t.string :state_root, null: false, limit: 64

      # Компоненти state_root для незалежної верифікації (BLOCKER-6)
      t.decimal :total_scc, precision: 30, scale: 4, null: false
      t.string :chain_hash, null: false
      t.datetime :anchored_at, null: false

      # L1 транзакція
      t.string :tx_hash, limit: 66
      t.bigint :block_number
      t.bigint :gas_used

      # Статус anchoring операції
      t.integer :status, null: false, default: 0

      # Помилка (якщо є)
      t.string :error_message, limit: 500

      t.timestamps
    end

    add_index :ethereum_anchors, :state_root, unique: true
    add_index :ethereum_anchors, :tx_hash, unique: true, where: "tx_hash IS NOT NULL"
    add_index :ethereum_anchors, :status
    add_index :ethereum_anchors, :created_at
  end
end

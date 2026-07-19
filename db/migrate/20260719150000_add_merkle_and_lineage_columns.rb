# frozen_string_literal: true

# ARCH.12 Фаза 1а + MRV.1 lineage: Merkle state_root (Eth-L1) + credit→measurements вікна.
# Схема-only (data-INSERT'и заборонені анкером init_consolidated); усі колонки
# nullable / fast-default → StrongMigrations-safe. ADD COLUMN на партиційованій
# blockchain_transactions каскадиться Postgres'ом на всі партиції.
class AddMerkleAndLineageColumns < ActiveRecord::Migration[8.1]
  def change
    # Merkle-якір: вікно телеметрія-листя + версіонування кореня (0=legacy flat, 1=merkle).
    # subtree_roots = упорядкований tier2-масив [{cluster_id: nil|int, root: hex}] —
    # verify_state_root самодостатній O(#кластерів) і переживає ретеншн-дроп партицій.
    add_column :ethereum_anchors, :window_from, :timestamp
    add_column :ethereum_anchors, :leaf_count, :integer, default: 0
    add_column :ethereum_anchors, :root_version, :integer, default: 0, null: false
    add_column :ethereum_anchors, :subtree_roots, :jsonb

    # Watermark-курсор lineage: позиція останнього лога, спожитого mint-вікном дерева.
    add_column :wallets, :lineage_cursor_at, :timestamp
    add_column :wallets, :lineage_cursor_log_id, :bigint

    # Вікно вимірів mint-інтенту (від курсора до курсора) + Merkle-корінь вікна.
    add_column :blockchain_transactions, :telemetry_window_from_at, :timestamp
    add_column :blockchain_transactions, :telemetry_window_from_id, :bigint
    add_column :blockchain_transactions, :telemetry_window_to_at, :timestamp
    add_column :blockchain_transactions, :telemetry_window_to_id, :bigint
    add_column :blockchain_transactions, :telemetry_merkle_root, :string, limit: 64
    add_column :blockchain_transactions, :telemetry_lineage_version, :integer
  end
end

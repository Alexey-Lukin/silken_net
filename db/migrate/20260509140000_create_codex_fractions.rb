# frozen_string_literal: true

# Phase 3 — Identity 🛡 — single-fraction-per-user table for the Codex.
#
# Why a separate table (not a `codex_fraction_id` column on `users`):
#   * keeps the User model lean (Phase 5 may add Discovery rows that scan
#     fraction history; isolating the relation makes it scope-cheap);
#   * `dependent: :destroy` on a side-table is safer than a column reset;
#   * UNIQUE `user_id` enforces "one active fraction" at the DB level —
#     no application-level race between the controller and the
#     `FractionChangeService` can ever leave two rows for the same user.
class CreateCodexFractions < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_fractions do |t|
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: { unique: true, name: "index_codex_fractions_on_user_unique" }
      t.references :codex_node,
                   null: false,
                   foreign_key: { on_delete: :restrict },
                   index: true

      # Denormalised from `codex_nodes.archetype_key` for cheap filters
      # ("how many users picked the `cold_wallet` archetype?") without a
      # join. Kept in sync inside `Codex::FractionChangeService`.
      t.string :archetype_key, null: false, limit: 64

      # `chosen_at`     — first-ever pick (immutable),
      # `last_changed_at` — most recent re-pick (used by the 7-day cooldown).
      t.datetime :chosen_at,       null: false
      t.datetime :last_changed_at, null: false

      # Optional Tailwind token (e.g. `status-info`) used by the Profile
      # badge — defaults to the Node's realm accent at controller level.
      t.string :house_color_token, limit: 64

      t.timestamps
    end

    add_index :codex_fractions, :archetype_key
    add_index :codex_fractions, :codex_node_id, name: "index_codex_fractions_on_node"
    add_index :codex_fractions, :last_changed_at, order: { last_changed_at: :desc }
  end
end

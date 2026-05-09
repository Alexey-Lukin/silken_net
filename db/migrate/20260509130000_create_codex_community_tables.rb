# frozen_string_literal: true

# Codex Phase 2 — Community layer.
#
# Adds two tables to support the social interactions defined in
# `docs/04_05_Codex_Lore_Module.md` §2.3 + §2.4:
#
#   * `codex_comments`     — polymorphic single-level threaded discussion;
#                            soft-hide via `hidden_at` (admin moderation
#                            never deletes), per-row flag metadata for
#                            future Phase-3 moderation queue.
#   * `codex_attunements`  — semantic "I tune to this archetype" relation;
#                            UNIQUE per (user, node), counter_cache fed
#                            into `codex_nodes.attunement_count` (column
#                            already exists since Phase 1).
#
# Counter columns (`comments_count`, `attunement_count`) are already
# present on `codex_nodes` from the Phase-1 squashed migration, so no
# `add_column` is needed there.
class CreateCodexCommunityTables < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_comments do |t|
      # Polymorphic association — Phase 2 only writes "Codex::Node",
      # but the column shape lets future phases (e.g. comments on
      # `Codex::Match` recap) reuse the same table without a migration.
      t.string  :commentable_type, null: false
      t.bigint  :commentable_id,   null: false

      t.references :user, null: false, foreign_key: true
      # Self-reference allowing exactly one nesting level — enforced in
      # the model, not the schema (DB-level CHECK would over-constrain
      # future deeper-thread experiments).
      t.references :parent, null: true,
                            foreign_key: { to_table: :codex_comments },
                            index: true

      t.text :body_md, null: false

      # Moderation surface — soft hide rather than destroy preserves
      # accountability per `docs/04_05` §5 (CommentPolicy: admin+ "hide,
      # not delete").
      t.datetime :flagged_at
      t.string   :flag_reason
      t.references :hidden_by_admin,
                   foreign_key: { to_table: :users },
                   index: true,
                   null: true
      t.datetime :hidden_at

      t.timestamps
    end

    add_index :codex_comments,
              %i[commentable_type commentable_id created_at],
              order: { created_at: :desc },
              name: "index_codex_comments_on_commentable_and_created_at"

    create_table :codex_attunements do |t|
      t.references :user, null: false, foreign_key: true
      t.references :codex_node,
                   null: false,
                   foreign_key: true,
                   index: true

      # 1..5 — enforced both in the model (validates :inclusion) and
      # at the DB level via the CHECK constraint so any direct INSERT
      # outside ActiveRecord still rejects out-of-band values.
      t.integer  :intensity, null: false, default: 3
      # ≤ 280 chars — Twitter-bio analogue. Length validated in the model;
      # DB column is plain text to keep migrations cheap if we later
      # raise the cap via DAO.
      t.string   :quote
      t.datetime :started_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps
    end

    add_index :codex_attunements,
              %i[user_id codex_node_id],
              unique: true,
              name: "index_codex_attunements_on_user_and_node_unique"

    # DB-level safety net. Model carries the canonical validation.
    add_check_constraint :codex_attunements,
                         "intensity BETWEEN 1 AND 5",
                         name: "codex_attunements_intensity_range"
  end
end

# frozen_string_literal: true

# Codex Phase 5 — Discovery layer.
#
# Adds two tables per `docs/04_05` §2.7 + §2.8:
#
#   * `codex_discoveries`     — log of "I unlocked Node X via trigger Y".
#                               UNIQUE per (user, node) — every card is
#                               unlocked at most once per user.
#   * `codex_discovery_rules` — DAO-editable registry of unlock conditions.
#                               Replaces hard-coded if-elsif chains so
#                               new cards can be wired without redeploy.
#
# Why integer-backed enums for `trigger_type` / `condition_type`:
#   * smaller indexes (4B vs 16B average for VARCHAR keys);
#   * Rails 8 enum DSL supports both string + integer; we follow project
#     convention (TelemetryLog.bio_status is string-backed for UI but
#     internal-only fields are int-backed).
#
# Counter cache `codex_nodes.discovery_count` already ships from Phase 1;
# we wire the `counter_cache: :discovery_count` association in the model.
#
# The `trigger_ref_*` polymorphic columns let a Discovery row point at the
# concrete artefact that triggered it (a `TelemetryLog`, a `Codex::Match`,
# a `Codex::Fraction`, a `Codex::Attunement`, a `BlockchainTransaction`).
# Polymorphic kept loose — no FK, no `dependent: :destroy`. If the source
# disappears the Discovery is still a fact.
class CreateCodexDiscoveries < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_discoveries do |t|
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: true
      t.references :codex_node,
                   null: false,
                   foreign_key: { on_delete: :restrict },
                   index: true

      # Enum: telemetry_observation(0) | manual_unlock(1) |
      #       match_milestone(2) | fraction_choice(3) |
      #       attunement_streak(4) | oracle_seasonal(5)
      t.integer :trigger_type, null: false, default: 0

      # Polymorphic source — kept loose, no FK.
      t.string :trigger_ref_type
      t.bigint :trigger_ref_id

      t.datetime :unlocked_at, null: false
      t.timestamps
    end

    add_index :codex_discoveries,
              [ :user_id, :codex_node_id ],
              unique: true,
              name: "idx_codex_discoveries_user_node_uniq"

    add_index :codex_discoveries,
              [ :trigger_ref_type, :trigger_ref_id ],
              name: "idx_codex_discoveries_trigger_ref"

    add_index :codex_discoveries,
              [ :user_id, :unlocked_at ],
              order: { unlocked_at: :desc },
              name: "idx_codex_discoveries_user_recent"

    create_table :codex_discovery_rules do |t|
      t.string :name, null: false

      t.references :codex_node,
                   null: false,
                   foreign_key: { on_delete: :restrict },
                   index: true

      # Enum: tree_observation_minutes(0) | acoustic_class_count(1) |
      #       cluster_visited(2) | match_count(3) |
      #       attunement_streak_days(4) | firmware_version_seen(5) |
      #       oracle_dispatched(6)
      t.integer :condition_type, null: false

      t.integer :threshold_value, null: false, default: 1

      # Free-form parameters: regex for region, archetype filter, etc.
      t.jsonb :params, null: false, default: {}

      t.boolean :active, null: false, default: true

      t.references :created_by_user,
                   null: false,
                   foreign_key: { to_table: :users, on_delete: :restrict },
                   index: true

      t.timestamps
    end

    # Hot-path index for the rule cache loader (`active_only` scope).
    add_index :codex_discovery_rules,
              [ :active, :condition_type ],
              name: "idx_codex_discovery_rules_active_condition"
  end
end

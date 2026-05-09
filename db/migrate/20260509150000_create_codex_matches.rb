# frozen_string_literal: true

# Codex Phase 4 — Battle layer.
#
# Adds the partitioned `codex_matches` table per `docs/04_05` §2.6.
#
# Why RANGE-partitioned by `created_at` (mirrors blockchain_transactions /
# telemetry_logs):
#   * Battle Arena is expected to be the most-written Codex surface (Elo
#     duels are cheap, gamified, and addictive). At 100M+ rows the
#     UNIQUE-PK BTREE on a non-partitioned table becomes a contention
#     hotspot. RANGE partitioning lets us drop / archive old months
#     atomically without VACUUM hell.
#   * The composite PK `(id, created_at)` matches the project standard
#     (see `BlockchainTransaction.find_with_partition_pruning`).
#   * `PartitionMaintenanceWorker` already handles month-rollover; we
#     just enroll `codex_matches` in its `PARTITIONED_TABLES` list.
#
# Initial partitions seeded inline:
#   * `codex_matches_default` — catch-all so unexpected-date inserts
#     don't 500 (production DOES NOT remove this — see below).
#   * 6 month windows starting at the migration's running month.
#
# Indices replicate the read patterns enumerated in §2.6:
#   * `(user_id, created_at DESC)` — own-history feed
#   * `(left_node_id, right_node_id)` — replay-protection lookups by
#     pair (when validating `pair_seed`)
#   * `realm_id` — leaderboard scoping
#
# Foreign keys: NO cascade on user/realm/node delete. Battle history is
# audit-grade; if a user is wiped we keep the match rows pointing at
# whatever the DB allows (the user_id is not used for moderation, and
# `_default` partition prevents data loss).
#
# Strong-migrations: the partitioned-table DDL pattern used here is the
# same one shipped in the squashed `init_consolidated`. Wrapped in
# `safety_assured` because Strong::Migrations rejects raw SQL by default.
class CreateCodexMatches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  PARTITIONED_TABLE = "codex_matches"

  def up
    safety_assured do
      execute <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{PARTITIONED_TABLE} (
          id            bigserial NOT NULL,
          user_id       bigint    NOT NULL,
          codex_realm_id bigint   NOT NULL,
          left_node_id   bigint   NOT NULL,
          right_node_id  bigint   NOT NULL,
          winner_node_id bigint,
          pair_seed      varchar(64) NOT NULL,
          elo_delta_left  integer NOT NULL DEFAULT 0,
          elo_delta_right integer NOT NULL DEFAULT 0,
          created_at     timestamp(6) NOT NULL,
          updated_at     timestamp(6) NOT NULL,
          PRIMARY KEY (id, created_at)
        ) PARTITION BY RANGE (created_at);
      SQL

      # _default partition — catches inserts outside the explicit ranges
      # so the application never 500s on a clock-skew row.
      execute <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{PARTITIONED_TABLE}_default
        PARTITION OF #{PARTITIONED_TABLE} DEFAULT;
      SQL

      # 6 months of forward partitions starting from the *previous* month
      # (so a backfill / time-travelling spec can still write).
      anchor = Time.current.utc.beginning_of_month - 1.month
      6.times do |i|
        month_start = anchor + i.months
        ensure_partition(month_start)
      end

      add_index PARTITIONED_TABLE, [ :user_id, :created_at ],
                order: { created_at: :desc },
                name: "idx_codex_matches_user_created"
      add_index PARTITIONED_TABLE, [ :left_node_id, :right_node_id ],
                name: "idx_codex_matches_pair"
      add_index PARTITIONED_TABLE, :codex_realm_id,
                name: "idx_codex_matches_realm"
      add_index PARTITIONED_TABLE, :pair_seed,
                name: "idx_codex_matches_pair_seed"

      add_foreign_key PARTITIONED_TABLE, :users,        column: :user_id
      add_foreign_key PARTITIONED_TABLE, :codex_realms, column: :codex_realm_id
      add_foreign_key PARTITIONED_TABLE, :codex_nodes,  column: :left_node_id
      add_foreign_key PARTITIONED_TABLE, :codex_nodes,  column: :right_node_id
      add_foreign_key PARTITIONED_TABLE, :codex_nodes,  column: :winner_node_id
    end
  end

  def down
    safety_assured do
      execute "DROP TABLE IF EXISTS #{PARTITIONED_TABLE} CASCADE;"
    end
  end

  private

  def ensure_partition(month_start)
    range_from = month_start.strftime("%Y-%m-%d 00:00:00")
    range_to   = (month_start + 1.month).strftime("%Y-%m-%d 00:00:00")
    name       = "#{PARTITIONED_TABLE}_y#{month_start.strftime('%Y')}m#{month_start.strftime('%m')}"

    execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{name}
      PARTITION OF #{PARTITIONED_TABLE}
      FOR VALUES FROM ('#{range_from}') TO ('#{range_to}');
    SQL
  end
end

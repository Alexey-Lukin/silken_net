# frozen_string_literal: true

# P1 Fix: blockchain_transactions RANGE partitioning by created_at (monthly).
#
# At planetary scale (1B trees × monthly SCC minting ≈ 12B rows/year),
# sequential scans on a monolithic table degrade to minutes. Monthly
# partitioning enables partition pruning for time-range queries and
# efficient archival of old data.
#
# Strategy: rename → recreate as partitioned → migrate data → drop old.
# Analogous to existing telemetry_logs / gateway_telemetry_logs setup.
#
# NOTE: disable_ddl_transaction! is required because PostgreSQL does not allow
# some DDL operations (e.g. multiple schema changes) inside a single transaction
# when combined with safety_assured. The migration is idempotent by design.
class PartitionBlockchainTransactionsByCreatedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up # rubocop:disable Metrics/MethodLength
    safety_assured do
      # ─── Step 1: Rename existing table and its PK constraint to temporary names ───
      execute "ALTER TABLE public.blockchain_transactions RENAME TO blockchain_transactions_old"
      execute "ALTER INDEX public.blockchain_transactions_pkey RENAME TO blockchain_transactions_old_pkey"
      execute "ALTER SEQUENCE public.blockchain_transactions_id_seq OWNED BY public.blockchain_transactions_old.id"

      # Drop FK constraints from old table (they reference wallets/clusters — will be re-created on new table)
      execute "ALTER TABLE public.blockchain_transactions_old DROP CONSTRAINT IF EXISTS fk_rails_7f57af4001"
      execute "ALTER TABLE public.blockchain_transactions_old DROP CONSTRAINT IF EXISTS fk_rails_d3cc5df71d"

      # ─── Step 2: Create new partitioned table ───
      execute <<~SQL
        CREATE TABLE public.blockchain_transactions (
          id bigint NOT NULL,
          wallet_id bigint,
          amount numeric,
          token_type integer,
          status integer,
          tx_hash character varying,
          notes text,
          created_at timestamp(6) without time zone NOT NULL,
          updated_at timestamp(6) without time zone NOT NULL,
          to_address character varying,
          error_message text,
          sourceable_id bigint,
          sourceable_type character varying,
          cluster_id bigint,
          locked_points integer,
          gas_price numeric,
          gas_used numeric,
          cumulative_gas_cost numeric,
          block_number bigint,
          nonce integer,
          sent_at timestamp(6) without time zone,
          confirmed_at timestamp(6) without time zone,
          chainlink_request_id character varying,
          zk_proof_ref character varying,
          blockchain_network character varying DEFAULT 'evm'::character varying
        ) PARTITION BY RANGE (created_at)
      SQL

      # ─── Step 3: Reassign sequence ownership ───
      execute "ALTER SEQUENCE public.blockchain_transactions_id_seq OWNED BY public.blockchain_transactions.id"

      # ─── Step 4: Set id default from sequence ───
      execute <<~SQL
        ALTER TABLE ONLY public.blockchain_transactions
          ALTER COLUMN id SET DEFAULT nextval('public.blockchain_transactions_id_seq'::regclass)
      SQL

      # ─── Step 5: Create default partition (catches data outside defined ranges) ───
      execute <<~SQL
        CREATE TABLE public.blockchain_transactions_default
          PARTITION OF public.blockchain_transactions DEFAULT
      SQL

      # ─── Step 6: Create monthly partitions (y2026m01..y2026m06) ───
      (1..6).each do |month|
        partition_name = format("blockchain_transactions_y2026m%02d", month)
        range_from = format("2026-%02d-01 00:00:00", month)
        range_to = if month == 12
                     "2027-01-01 00:00:00"
        else
                     format("2026-%02d-01 00:00:00", month + 1)
        end

        execute <<~SQL
          CREATE TABLE public.#{partition_name}
            PARTITION OF public.blockchain_transactions
            FOR VALUES FROM ('#{range_from}') TO ('#{range_to}')
        SQL
      end

      # ─── Step 7: Add composite primary key (partition key must be in PK) ───
      execute <<~SQL
        ALTER TABLE ONLY public.blockchain_transactions
          ADD CONSTRAINT blockchain_transactions_pkey PRIMARY KEY (id, created_at)
      SQL

      # ─── Step 8: Migrate data from old table ───
      execute <<~SQL
        INSERT INTO public.blockchain_transactions
          SELECT * FROM public.blockchain_transactions_old
      SQL

      # ─── Step 9: Drop old table ───
      execute "DROP TABLE public.blockchain_transactions_old"

      # ─── Step 10: Re-create indexes ───
      # NOTE: PostgreSQL does not support CONCURRENTLY on partitioned tables,
      # so regular CREATE INDEX is used. Indexes propagate to all partitions automatically.
      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_block_number
          ON public.blockchain_transactions USING btree (block_number)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_chainlink_request_id
          ON public.blockchain_transactions USING btree (chainlink_request_id)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_cluster_id
          ON public.blockchain_transactions USING btree (cluster_id)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_confirmed_at
          ON public.blockchain_transactions USING btree (confirmed_at)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_sourceable
          ON public.blockchain_transactions USING btree (sourceable_type, sourceable_id)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_wallet_id
          ON public.blockchain_transactions USING btree (wallet_id)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_wallet_id_and_status
          ON public.blockchain_transactions USING btree (wallet_id, status)
      SQL

      execute <<~SQL
        CREATE INDEX index_blockchain_transactions_on_tx_hash
          ON public.blockchain_transactions USING btree (tx_hash) WHERE (tx_hash IS NOT NULL)
      SQL

      # ─── Step 11: Re-create foreign key constraints ───
      # NOTE: Partitioned tables use ALTER TABLE (without ONLY) for FK propagation
      execute <<~SQL
        ALTER TABLE public.blockchain_transactions
          ADD CONSTRAINT fk_blockchain_transactions_wallet_id
          FOREIGN KEY (wallet_id) REFERENCES public.wallets(id)
      SQL

      execute <<~SQL
        ALTER TABLE public.blockchain_transactions
          ADD CONSTRAINT fk_blockchain_transactions_cluster_id
          FOREIGN KEY (cluster_id) REFERENCES public.clusters(id)
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Reversing partitioning requires manual data migration. " \
      "Use a separate migration to consolidate partitions back."
  end
end

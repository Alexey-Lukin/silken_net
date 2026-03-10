# frozen_string_literal: true

class AddChainlinkOracleFieldsToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :chainlink_request_id, :string
    add_column :telemetry_logs, :oracle_status, :string, default: "pending"

    # [SCALE]: telemetry_logs is PARTITION BY RANGE (created_at).
    # Full index on chainlink_request_id for callback lookups (sparse — only dispatched rows have a value).
    add_index :telemetry_logs, :chainlink_request_id

    # [SCALE]: Partial indexes on oracle_status — at billions of rows most are 'pending',
    # so a full index wastes disk and I/O. Only index the active/terminal states the system queries.
    add_index :telemetry_logs, :oracle_status, where: "oracle_status = 'dispatched'", name: "idx_telemetry_logs_oracle_dispatched"
    add_index :telemetry_logs, :oracle_status, where: "oracle_status = 'fulfilled'",  name: "idx_telemetry_logs_oracle_fulfilled"
    add_index :telemetry_logs, :oracle_status, where: "oracle_status = 'failed'",     name: "idx_telemetry_logs_oracle_failed"
  end
end

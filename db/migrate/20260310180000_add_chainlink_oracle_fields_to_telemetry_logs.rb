# frozen_string_literal: true

class AddChainlinkOracleFieldsToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :chainlink_request_id, :string
    add_column :telemetry_logs, :oracle_status, :string, default: "pending"

    add_index :telemetry_logs, :chainlink_request_id
    add_index :telemetry_logs, :oracle_status
  end
end

# frozen_string_literal: true

class AddIotexVerificationToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :verified_by_iotex, :boolean, default: false, null: false
    add_column :telemetry_logs, :zk_proof_ref, :string
  end
end

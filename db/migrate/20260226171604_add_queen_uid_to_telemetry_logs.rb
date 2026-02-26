class AddQueenUidToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :queen_uid, :string
  end
end

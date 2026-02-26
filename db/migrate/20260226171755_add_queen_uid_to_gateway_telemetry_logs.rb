class AddQueenUidToGatewayTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :gateway_telemetry_logs, :queen_uid, :string
  end
end

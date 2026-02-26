class CreateGatewayTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :gateway_telemetry_logs do |t|
      t.references :gateway, null: false, foreign_key: true
      t.decimal :battery_level
      t.integer :signal_strength

      t.timestamps
    end
  end
end

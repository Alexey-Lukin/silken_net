class CreateTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :telemetry_logs do |t|
      t.references :tree, null: false, foreign_key: true
      t.decimal :temperature_c
      t.integer :acoustic_events
      t.decimal :growth_points
      t.integer :bio_status
      t.integer :piezo_voltage_mv
      t.boolean :tamper_detected
      t.decimal :z_value

      t.timestamps
    end
  end
end

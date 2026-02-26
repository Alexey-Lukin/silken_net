class AddMissingFieldsToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :voltage_mv, :integer
    add_column :telemetry_logs, :metabolism_s, :integer
    add_column :telemetry_logs, :mesh_ttl, :integer
  end
end

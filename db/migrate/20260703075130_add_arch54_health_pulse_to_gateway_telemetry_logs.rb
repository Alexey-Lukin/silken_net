class AddArch54HealthPulseToGatewayTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :gateway_telemetry_logs, :uptime_min, :integer
    add_column :gateway_telemetry_logs, :cifo_fill, :integer
    add_column :gateway_telemetry_logs, :lora_rx_drops, :integer
    add_column :gateway_telemetry_logs, :coap_fail_count, :integer
    add_column :gateway_telemetry_logs, :health_flags, :integer
  end
end

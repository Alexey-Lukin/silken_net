class AddSatelliteVerificationToEwsAlerts < ActiveRecord::Migration[8.1]
  def change
    add_column :ews_alerts, :satellite_status, :integer, default: 0, null: false
    add_column :ews_alerts, :dclimate_ref, :string
  end
end

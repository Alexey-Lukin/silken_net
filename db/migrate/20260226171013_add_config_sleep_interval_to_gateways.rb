class AddConfigSleepIntervalToGateways < ActiveRecord::Migration[8.1]
  def change
    add_column :gateways, :config_sleep_interval_s, :integer
  end
end

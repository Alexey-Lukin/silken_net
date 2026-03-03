class SyncSchemaWithModels < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :latest_voltage_mv, :integer
    add_column :hardware_keys, :previous_aes_key_hex, :string
    add_column :hardware_keys, :rotated_at, :datetime
    add_column :clusters, :environmental_settings, :jsonb
    add_column :clusters, :health_index, :float
  end
end

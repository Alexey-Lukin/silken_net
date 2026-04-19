# frozen_string_literal: true

class AddPuroEarthCorcRefToMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_records, :puro_earth_corc_ref, :string
  end
end

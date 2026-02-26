class AddActionTypeToMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_records, :action_type, :integer
  end
end

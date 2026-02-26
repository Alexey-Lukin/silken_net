class UpgradeMaintenanceRecordsToPolymorphic < ActiveRecord::Migration[8.1]
  def change
    remove_reference :maintenance_records, :tree, index: true
    add_reference :maintenance_records, :maintainable, polymorphic: true, index: true
  end
end

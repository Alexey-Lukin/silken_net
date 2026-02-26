class CreateMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_records do |t|
      t.references :tree, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :action_taken
      t.datetime :performed_at

      t.timestamps
    end
  end
end

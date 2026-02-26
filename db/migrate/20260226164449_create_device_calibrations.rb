class CreateDeviceCalibrations < ActiveRecord::Migration[8.1]
  def change
    create_table :device_calibrations do |t|
      t.references :tree, null: false, foreign_key: true
      t.decimal :temp_offset
      t.integer :acoustic_offset

      t.timestamps
    end
  end
end

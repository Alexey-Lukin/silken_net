class CreateActuators < ActiveRecord::Migration[8.1]
  def change
    create_table :actuators do |t|
      t.references :gateway, null: false, foreign_key: true
      t.string :name
      t.integer :device_type
      t.integer :state

      t.timestamps
    end
  end
end

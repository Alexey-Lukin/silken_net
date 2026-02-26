class CreateTreeFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :tree_families do |t|
      t.string :name
      t.integer :base_resistance
      t.decimal :critical_z_min
      t.decimal :critical_z_max

      t.timestamps
    end
  end
end

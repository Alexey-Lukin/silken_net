class CreateTrees < ActiveRecord::Migration[8.1]
  def change
    create_table :trees do |t|
      t.string :did
      t.decimal :latitude
      t.decimal :longitude
      t.decimal :altitude
      t.references :cluster, null: false, foreign_key: true
      t.references :tree_family, null: false, foreign_key: true

      t.timestamps
    end
    add_index :trees, :did, unique: true
  end
end

class CreateSystemParameters < ActiveRecord::Migration[8.1]
  def change
    create_table :system_parameters do |t|
      t.string :key, null: false
      t.string :value, null: false
      t.string :value_type, null: false, default: "string"
      t.string :category, null: false, default: "general"
      t.text :description
      t.decimal :min_value
      t.decimal :max_value
      t.string :source, null: false, default: "default"
      t.references :updated_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
    add_index :system_parameters, :key, unique: true
    add_index :system_parameters, :category
  end
end

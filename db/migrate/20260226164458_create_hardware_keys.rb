class CreateHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :hardware_keys do |t|
      t.references :tree, null: false, foreign_key: true
      t.string :aes_key

      t.timestamps
    end
  end
end

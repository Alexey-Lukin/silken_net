class CreateTinyMlModels < ActiveRecord::Migration[8.1]
  def change
    create_table :tiny_ml_models do |t|
      t.string :version
      t.string :target_pest
      t.text :binary_weights_payload

      t.timestamps
    end
  end
end

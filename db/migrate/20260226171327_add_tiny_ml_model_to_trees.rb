class AddTinyMlModelToTrees < ActiveRecord::Migration[8.1]
  def change
    add_reference :trees, :tiny_ml_model, null: false, foreign_key: true
  end
end

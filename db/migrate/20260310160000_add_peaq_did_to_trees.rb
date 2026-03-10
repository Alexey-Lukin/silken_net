# frozen_string_literal: true

class AddPeaqDidToTrees < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :peaq_did, :string
    add_index :trees, :peaq_did, unique: true
  end
end

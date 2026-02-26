class AddOrganizationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :organization, null: false, foreign_key: true
  end
end

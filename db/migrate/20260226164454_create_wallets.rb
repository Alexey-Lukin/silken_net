class CreateWallets < ActiveRecord::Migration[8.1]
  def change
    create_table :wallets do |t|
      t.references :tree, null: false, foreign_key: true
      t.decimal :balance
      t.string :crypto_public_address

      t.timestamps
    end
  end
end

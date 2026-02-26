class CreateBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :blockchain_transactions do |t|
      t.references :wallet, null: false, foreign_key: true
      t.decimal :amount
      t.integer :token_type
      t.integer :status
      t.string :tx_hash
      t.text :notes

      t.timestamps
    end
  end
end

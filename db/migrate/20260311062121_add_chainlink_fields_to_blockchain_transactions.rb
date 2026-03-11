class AddChainlinkFieldsToBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :blockchain_transactions, :chainlink_request_id, :string
    add_column :blockchain_transactions, :zk_proof_ref, :string
    add_index :blockchain_transactions, :chainlink_request_id
  end
end

class AddBlockchainNetworkToBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :blockchain_transactions, :blockchain_network, :string, default: "evm"
  end
end

class AddLockedBalanceToWallets < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :locked_balance, :decimal, default: 0, null: false
  end
end

class AddToucanBridgedBalanceToWallets < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :toucan_bridged_balance, :decimal, precision: 18, scale: 4, default: 0, null: false
  end
end

# frozen_string_literal: true

class AddEsgRetiredBalanceToWallets < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :esg_retired_balance, :decimal, precision: 24, scale: 6, default: 0, null: false
  end
end

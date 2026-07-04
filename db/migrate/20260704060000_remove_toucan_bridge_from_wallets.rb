# frozen_string_literal: true

# [E.66] Toucan-prune: flow DEAD (0 enqueue-callerів), прод-деплою ще не було →
# безпечний drop без two-step ignored_columns. Expansion воскресає з git при E.20-go.
class RemoveToucanBridgeFromWallets < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :wallets, :toucan_bridged_balance, :decimal, precision: 24, scale: 6, default: 0.0, null: false
    end
  end
end

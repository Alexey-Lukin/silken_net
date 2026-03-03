# frozen_string_literal: true

# Пастка "Останнього дерева": якщо весь кластер загинув (пожежа, повінь),
# @source_tree та @cluster.trees.active обидва повертають nil,
# і аудит-транзакція slashing не записується взагалі.
#
# Рішення: wallet_id стає необов'язковим, а cluster_id — запасним власником
# аудит-запису, коли жодного живого дерева-носія немає.
class MakeWalletOptionalInBlockchainTransactions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :blockchain_transactions, :wallet_id, true
    add_reference :blockchain_transactions, :cluster, null: true, foreign_key: true
  end
end

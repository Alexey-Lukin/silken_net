# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class BlockchainTransactionBlueprint < Blueprinter::Base
  identifier :id

  # 🔴 [ARCH.98] Провенанс резолвиться ДВОМА координатами, тож обидві мусять бути й
  # тут: cluster-sourced рухи (Celo-винагорода, слеш останнього дерева) живуть без
  # гаманця, і `tree_did` для них `null` ЗА ПОБУДОВОЮ. `tree_did` свідомо НЕ
  # перейменовано — це чинний контракт дроту, а не опис поля.
  # ⚠️ Пара тримається разом із HTML-коміркою «Джерело» саме тому, що один екшен
  # обслуговує обидва формати: добудова лише одного боку і є клас [ARCH.90].
  view :index do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :created_at
    field(:explorer_url) { |tx| tx.explorer_url }
    field(:tree_did) { |tx| tx.wallet&.tree&.did }
    field(:cluster_name) { |tx| tx.cluster&.name }
  end

  view :show do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :locked_points,
           :notes, :error_message, :created_at, :updated_at,
           :gas_price, :gas_used, :cumulative_gas_cost,
           :block_number, :nonce, :sent_at, :confirmed_at
    field(:explorer_url) { |tx| tx.explorer_url }
    field(:cluster_name) { |tx| tx.cluster&.name }
    association :wallet, blueprint: WalletBlueprint, view: :with_tree
  end
end

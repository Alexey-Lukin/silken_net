# frozen_string_literal: true

class BlockchainTransactionBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :created_at
    field(:explorer_url) { |tx| tx.explorer_url }
    field(:tree_did) { |tx| tx.wallet&.tree&.did }
  end

  view :show do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :locked_points,
           :notes, :error_message, :created_at, :updated_at
    field(:explorer_url) { |tx| tx.explorer_url }
    association :wallet, blueprint: WalletBlueprint, view: :with_tree
  end
end

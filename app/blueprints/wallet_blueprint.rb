# frozen_string_literal: true

class WalletBlueprint < Blueprinter::Base
  identifier :id

  fields :balance, :scc_balance, :crypto_public_address

  view :with_tree do
    association :tree, blueprint: TreeBlueprint, view: :minimal
  end
end

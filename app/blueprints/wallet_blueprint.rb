# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class WalletBlueprint < Blueprinter::Base
  identifier :id

  fields :balance, :crypto_public_address

  view :show do
    association :tree, blueprint: TreeBlueprint, view: :minimal
  end

  view :with_tree do
    association :tree, blueprint: TreeBlueprint, view: :minimal
  end

  # Lightweight view for the /balance endpoint — returns key financial figures
  # without tree/org associations to keep the response fast for Turbo Frame lazy-loads.
  view :balance do
    exclude :crypto_public_address
    field :scc_balance
    field :locked_balance
    field :available_balance
    field :esg_retired_balance
  end

  # Lightweight view for the /metadata endpoint — returns blockchain identity
  # fields used by mobile clients and third-party integrators.
  view :metadata do
    field :crypto_public_address
    field :locked_balance
    field :available_balance
    field :esg_retired_balance
    field :network do |_wallet, _options|
      "Polygon PoS (Mainnet)"
    end
  end
end

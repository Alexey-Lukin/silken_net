# frozen_string_literal: true

class TreeBlueprint < Blueprinter::Base
  identifier :id

  view :minimal do
    fields :did, :status, :peaq_did
  end

  view :index do
    fields :did, :status, :peaq_did, :latitude, :longitude, :last_seen_at
    field(:current_stress) { |tree| tree.current_stress }
    field(:under_threat?) { |tree| tree.under_threat? }
    association :wallet, blueprint: WalletBlueprint do |tree|
      tree.wallet
    end
    field(:tree_family_name) { |tree| tree.tree_family&.name }
  end

  view :show do
    fields :did, :status, :peaq_did, :last_seen_at
    field(:current_stress) { |tree| tree.current_stress }
    field(:under_threat?) { |tree| tree.under_threat? }
    association :wallet, blueprint: WalletBlueprint do |tree|
      tree.wallet
    end
    field(:tree_family_name) { |tree| tree.tree_family&.name }
    field(:baseline_impedance) { |tree| tree.tree_family&.baseline_impedance }
  end
end

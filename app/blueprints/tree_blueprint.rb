# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.36, ⚖️ founder 2026-10-24] `peaq_did` не віддається: жодна сторінка його не друкує, а стеля
# JSON — те, що вже показує HTML (прецедент `AiInsightBlueprint`). Знято за ФОРМОЮ, не за
# чутливістю: DID публічний за побудовою (peaq-реєстр), тож «він і так публічний» — не підстава
# повертати.
class TreeBlueprint < Blueprinter::Base
  identifier :id

  view :minimal do
    fields :did, :status
  end

  view :index do
    fields :did, :status, :latitude, :longitude, :last_seen_at
    field(:current_stress) { |tree| tree.current_stress }
    field(:under_threat?) { |tree| tree.under_threat? }
    association :wallet, blueprint: WalletBlueprint do |tree|
      tree.wallet
    end
    field(:tree_family_name) { |tree| tree.tree_family&.name }
  end

  view :show do
    fields :did, :status, :last_seen_at
    field(:current_stress) { |tree| tree.current_stress }
    field(:under_threat?) { |tree| tree.under_threat? }
    association :wallet, blueprint: WalletBlueprint do |tree|
      tree.wallet
    end
    field(:tree_family_name) { |tree| tree.tree_family&.name }
  end
end

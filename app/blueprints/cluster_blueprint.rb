# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ClusterBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :region
  field(:health_index) { |cluster| cluster.health_index }
  field(:total_active_trees) { |cluster| cluster.total_active_trees }
  field(:geo_center) { |cluster| cluster.geo_center }
  field(:active_threats) { |cluster| cluster.active_threats? }

  view :show do
    field :geojson_polygon
    # [ARCH.103] Емісія — величина КЛАСТЕРА (⚖️-присуд: контрактної семантики не існує,
    # доки кластер несе кілька контрактів одночасно), тож вона поле кластера, а рядки
    # контрактів нижче несуть лише контрактні факти. Ключ дзеркалить HTML-сторінку
    # кластера (`net_cluster_emission`); точність — прецедент `contracts#stats`.
    field(:net_cluster_emission) do |cluster|
      BlockchainTransaction.for_cluster(cluster.id).net_minted_supply(:carbon_coin).to_f.round(4)
    end
    association :gateways, blueprint: GatewayBlueprint
    field(:naas_contracts) do |cluster|
      # ⚠️ `total_funding` — СХЕМНЕ імʼя: `as_json(only:)` МОВЧКИ ігнорує alias
      # (`:total_value` у цьому списку роками не віддавав нічого — виміряно).
      cluster.naas_contracts.as_json(only: [ :id, :status, :total_funding ])
    end
  end
end

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
    association :gateways, blueprint: GatewayBlueprint
    field(:naas_contracts) do |cluster|
      cluster.naas_contracts.as_json(only: [ :id, :status, :total_value, :emitted_tokens ])
    end
  end
end

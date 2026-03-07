# frozen_string_literal: true

module Dashboard
  class MapNode < ApplicationComponent
    def initialize(tree:)
      @tree = tree
    end

    def view_template
      # Цей div зчитається методом nodeTargetConnected у JS
      div(
        id: "map_node_#{@tree.id}",
        data_map_target: "node",
        data_did: @tree.did,
        data_lat: @tree.latitude.to_f,
        data_lng: @tree.longitude.to_f,
        data_stress: @tree.current_stress.to_f,
        data_charge: @tree.charge_percentage.to_i,
        data_status: @tree.status
      )
    end
  end
end

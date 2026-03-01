# frozen_string_literal: true

module Views
  module Components
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
            data_lat: @tree.latitude,
            data_lng: @tree.longitude,
            data_stress: @tree.current_stress,
            data_charge: @tree.charge_percentage,
            data_status: @tree.status
          )
        end
      end
    end
  end
end

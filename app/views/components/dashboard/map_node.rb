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
        data: {
          map_target: "node",
          did: @tree.did,
          lat: @tree.latitude.to_f,
          lng: @tree.longitude.to_f,
          stress: @tree.current_stress.to_f,
          charge: @tree.charge_percentage.to_i,
          status: @tree.status
        }
      )
    end
  end
end

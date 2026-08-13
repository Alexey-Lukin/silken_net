# SPDX-License-Identifier: AGPL-3.0-or-later
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
          # ⛔ [ARCH.99] `charge` тут БІЛЬШЕ НЕМА, і це не косметика: здорове дерево
          # давало 18 %, тож `charge < 30` у `map_controller` було істинне ЗАВЖДИ —
          # диз'юнкція згорталась, і смарагдовий колір гомеостазу був недосяжний за
          # побудовою. Карта фарбувала весь ліс жовтим назавжди.
          status: @tree.status
        }
      )
    end
  end
end

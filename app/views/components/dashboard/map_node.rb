# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class MapNode < ApplicationComponent
    # 🔴 [UI.4] Дім target-id вузла мапи: адресу називали рукою обидва боки —
    # цей компонент і `Tree#broadcast_map_update`. ⚠️ `dom_id(tree, :map_node)` тут
    # НЕ підходить: він вставляє `param_key` між префіксом і id, тобто дав би
    # `map_node_tree_42`, а не `map_node_42` — виміряно рантаймом, не виведено.
    def self.dom_id(tree_id) = "map_node_#{tree_id}"

    def initialize(tree:)
      @tree = tree
    end

    def view_template
      # Цей div зчитається методом nodeTargetConnected у JS
      div(
        id: self.class.dom_id(@tree.id),
        data: {
          map_target: "node",
          did: @tree.did,
          lat: @tree.latitude.to_f,
          lng: @tree.longitude.to_f,
          # [ARCH.84] Атрибут ВІДСУТНІЙ, коли стрес не виміряно — `.to_f` тут був
          # ридер-підстановкою (nil → 0.0 → смарагдовий «гомеостаз»). Відсутність
          # читає `map_controller` як окремий стан, а не як нуль.
          **(@tree.current_stress.nil? ? {} : { stress: @tree.current_stress }),
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

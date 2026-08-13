# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::MapNode do
  # [TEST.12] Реальний незбережений `Tree`, і фікстура годує ДЖЕРЕЛА, а не результати.
  # `current_stress` — не колонка, а похідна (`latest_stress_index.to_f`), тож мок, який
  # клав її напряму, робив саме перетворення неперевірним і дозволяв задати комбінацію,
  # недосяжну на реальному записі.
  # 🔴 [ARCH.99] Другою похідною тут був `charge_percentage`, і подача її напряму
  # ховала не одиницю, а ПОРІГ: `map_controller` розгалужувався на `charge < 30`, тоді
  # як реальний вхід дає 18 % завжди. Тобто фікстура приховувала не хибне число, а
  # згорнуту гілку — величину знято цілком, разом із самим атрибутом.
  #
  # 🔴 `status` тепер ходить через справжній enum (`active/dormant/removed/deceased`),
  # тому вигадані `"stress"`/`"anomaly"` тут більше неможливі: вони належать ІНШІЙ моделі
  # (`TelemetryLog#bio_status` — самозвіт здоровʼя з пакета), і саме через них єдиний
  # статус, на який зважає `map_controller.js`, не перевірявся ніде.
  def build_tree(id: 3, did: "SNET-00000003", latitude: 49.44, longitude: 32.06,
                 latest_stress_index: 0.3, latest_voltage_mv: 4744, status: :active)
    Tree.new(
      id: id,
      did: did,
      latitude: latitude,
      longitude: longitude,
      latest_stress_index: latest_stress_index,
      latest_voltage_mv: latest_voltage_mv,
      status: status
    )
  end

  def render_component(tree:)
    component_class.new(tree: tree).call
  end

  let(:tree) { build_tree }
  let(:html) { render_component(tree: tree) }

  describe "div ID" do
    it "renders the map_node div with the correct tree ID" do
      expect(html).to include('id="map_node_3"')
    end
  end

  describe "data attributes for Stimulus" do
    it "sets the map_target to node" do
      expect(html).to include('data-map-target="node"')
    end

    it "sets the DID data attribute" do
      expect(html).to include('data-did="SNET-00000003"')
    end

    it "sets the latitude data attribute" do
      expect(html).to include("data-lat=")
      expect(html).to include("49.44")
    end

    it "sets the longitude data attribute" do
      expect(html).to include("data-lng=")
      expect(html).to include("32.06")
    end

    it "sets the stress data attribute" do
      expect(html).to include("data-stress=")
      expect(html).to include("0.3")
    end

    # 🔴 [ARCH.99] Носій ВИДАЛЕННЯ. Доти пін вимагав `data-charge="72"` — і саме
    # цей атрибут згортав рішення в `map_controller`: здорове дерево давало 18 %,
    # тож `charge < 30` було істинне завжди, і смарагдовий гомеостаз лишався
    # недосяжним для БУДЬ-ЯКОГО вузла — карта фарбувала ліс жовтим назавжди.
    # Спека цього не бачила, бо фікстура подавала відсоток напряму.
    it "emits no charge attribute — the map must not branch on a fabricated level" do
      expect(html).not_to include("data-charge")
    end

    it "sets the status data attribute" do
      expect(html).to include('data-status="active"')
    end
  end

  describe "different tree statuses" do
    # 🔴 `removed` — ЄДИНЕ значення статусу, на яке зважає `map_controller.js`
    # (`if (stress > 0.8 || data.status === "removed")` форсує danger-маркер), і доти
    # воно не перевірялось НІДЕ: спека ходила вигаданими `"stress"`/`"anomaly"` з
    # чужої моделі. Шлях штатний — `Tree#decommission!` переводить сюди й шле
    # `broadcast_map_update`, тобто оператор вмикає саме цю гілку деінсталяцією.
    it "passes the one status the map controller actually branches on" do
      html = render_component(tree: build_tree(status: :removed))

      expect(html).to include('data-status="removed"')
    end

    it "renders the remaining lifecycle statuses verbatim" do
      %i[dormant deceased].each do |state|
        html = render_component(tree: build_tree(status: state))

        expect(html).to include(%(data-status="#{state}"))
      end
    end
  end

  describe "zero values" do
    # ⚠️ Пін на ЗНАЧЕННЯ, не на присутність атрибута: `data-stress=` рендериться
    # безумовно для будь-якого числа, тож попередня форма була зелена і при
    # правильній, і при зламаній обробці нуля.
    it "renders a zeroed node with explicit zeros, not blanks" do
      html = render_component(tree: build_tree(latest_stress_index: 0.0, latest_voltage_mv: 0))

      expect(html).to include('data-stress="0.0"')
    end
  end
end

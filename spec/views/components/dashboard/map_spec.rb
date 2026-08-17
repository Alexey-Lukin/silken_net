# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Map do
  # [TEST.12] Реальні незбережені записи. Дерева їдуть у `Dashboard::MapNode`,
  # чия фікстура вже годує ДЖЕРЕЛА — а тут доти лежали похідні напряму, тобто той
  # самий дефект, який у сусідній спеці закритий, жив далі в тій, що рендерить той
  # самий під-компонент. [ARCH.99] Другу похідну (`charge_percentage`) знято разом
  # із величиною; делегацію тримає стрес.
  def build_tree(id: 1, did: "SNET-00000001", latitude: 49.4444, longitude: 32.0597,
                 status: :active, latest_stress_index: 0.2, latest_voltage_mv: 5095)
    Tree.new(
      id: id,
      did: did,
      latitude: latitude,
      longitude: longitude,
      status: status,
      latest_stress_index: latest_stress_index,
      latest_voltage_mv: latest_voltage_mv
    )
  end

  # `stream_epoch` НЕ дефолтний (1) навмисно [SEC.25 Ф3]: якби епоха десь була
  # зашита константою замість того, щоб текти з організації, з одиницею це
  # лишилось би зеленим.
  # [UI.4] `map_total` компонент вимагає БЕЗ дефолту (забута проводка мусить падати
  # гучно), тож дефолт живе тут — і він чесний: «показано стільки ж, скільки є»,
  # тобто стан, у якому підстава не рендериться. Саму пару стереже власний
  # `describe` наприкінці файлу.
  def render_component(trees:, organization: Organization.new(id: 42, stream_epoch: 7), map_total: nil)
    ApplicationController.renderer.render(
      component_class.new(trees: trees, organization: organization, map_total: map_total || trees.size),
      layout: false
    )
  end

  let(:trees) { [ build_tree(id: 1, did: "SNET-00000001"), build_tree(id: 2, did: "SNET-00000002") ] }
  let(:html) { render_component(trees: trees) }

  describe "map container" do
    it "renders the Geospatial Matrix HUD label" do
      expect(html).to include("Geospatial Matrix")
    end

    it "renders the Stimulus map controller" do
      expect(html).to include('data-controller="map"')
    end

    it "renders the map data nodes container" do
      expect(html).to include('id="map_data_nodes"')
    end
  end

  describe "turbo stream subscription" do
    def subscribed_streams(rendered)
      rendered.scan(/signed-stream-name="([^"]+)"/).flatten
              .map { |s| Turbo::StreamsChannel.verified_stream_name(s) }
    end

    it "renders a turbo cable stream source for live updates" do
      expect(html).to include("turbo-cable-stream-source")
    end

    # Ім'я стріму детерміноване, тож голий літерал посадив би ВСІХ глядачів
    # у той самий канал і роздав координати й DID чужого флоту (клас SEC.25).
    # Дві різні організації обов'язкові: з однією пін мовчить на найправдо-
    # подібнішій підміні (будь-який фіксований id дорівнював би єдиному).
    it "scopes the stream to the viewer's own organization" do
      expect(subscribed_streams(html)).to eq([ "geospatial_matrix_org_42_e7" ])

      other = render_component(trees: trees, organization: Organization.new(id: 99, stream_epoch: 7))
      expect(subscribed_streams(other)).to eq([ "geospatial_matrix_org_99_e7" ])
    end

    # Глядач без організації адреси не має — підписки не існує (fail-closed),
    # решта мапи рендериться нормально.
    it "renders no subscription at all when the viewer has no organization" do
      orphan = render_component(trees: trees, organization: nil)

      expect(orphan).not_to include("turbo-cable-stream-source")
      expect(orphan).to include('id="map_data_nodes"')
    end
  end

  describe "live active nodes count" do
    it "renders the count of active trees" do
      expect(html).to include("Live Active Nodes: 2")
    end

    it "renders correct count for single tree" do
      html = render_component(trees: [ build_tree ])
      expect(html).to include("Live Active Nodes: 1")
    end
  end

  describe "MapNode delegation" do
    it "renders a map node div for each tree" do
      expect(html).to include('id="map_node_1"')
      expect(html).to include('id="map_node_2"')
    end

    it "renders DID data attribute" do
      expect(html).to include("SNET-00000001")
    end

    # Делегацію доводить не присутність вузла, а ВИВЕДЕНЕ значення в ньому.
    # [ARCH.99] Доти носієм тут був заряд; його знято разом із величиною, тож
    # делегацію тримає стрес — єдина похідна, що лишилась у вузлі (модель виводить
    # її з `latest_stress_index`). Пін падає і коли Map передасть під-компоненту
    # не те дерево, і коли зламається саме перетворення.
    it "carries each tree's derived stress down into its node" do
      expect(html).to include('data-stress="0.2"')
    end
  end

  describe "Leaflet CSS" do
    it "includes the Leaflet stylesheet link" do
      expect(html).to include("leaflet")
    end
  end

  describe "empty trees" do
    it "renders without errors when no trees provided" do
      html = render_component(trees: [])
      expect(html).to include("Live Active Nodes: 0")
    end
  end

  describe "HUD overlay" do
    # Доти цей блок звався «bottom overlay» і пінив рівно те саме, що приклад
    # вище, списавши відсутність координат на властивість Phlex; координатного
    # вузла тут не було ніколи, а єдиний HUD стоїть угорі ліворуч. Пінимо те,
    # що він реально несе й що ніхто не перевіряв: панель лежить НАД плитками
    # Leaflet і при цьому не перехоплює вказівник у мапи під собою.
    it "floats above the Leaflet tiles without stealing pointer events" do
      expect(html).to include("z-[400]")
      expect(html).to include("pointer-events-none")
    end
  end

  # 🔴 [UI.4] Стеля `MAP_NODE_LIMIT` ріже флот, і доти екран цього не оголошував
  # ніде — число зрізаної підмножини друкувалось як факт про ліс. Трійка потрібна
  # ЦІЛКОМ: без другого «500» на флоті в 10 000 невідрізнимі від повного покриття,
  # без третього пін проходив би й на компоненті, що друкує підставу ЗАВЖДИ (тоді
  # «показано N з N» стояло б під кожною здоровою мапою й знецінило б сигнал).
  describe "коли мапа показує лише частину флоту" do
    it "prints the ground under the node count" do
      truncated = render_component(trees: trees, map_total: 137)

      expect(truncated).to include("Live Active Nodes: 2")
      expect(truncated).to include(I18n.t("ui.measurement.coverage", measured: 2, total: 137))
    end

    it "stays SILENT about coverage when the whole fleet fits on the map" do
      full = render_component(trees: trees, map_total: 2)

      expect(full).to include("Live Active Nodes: 2")
      expect(full).not_to include(I18n.t("ui.measurement.coverage", measured: 2, total: 2))
    end

    # Ліхтар на РІШЕННЯ, а не на поведінку: пара свідомо без дефолту, бо `nil`
    # мовчав би так само, як «стеля не досягнута». Без цього прикладу перший,
    # кому обовʼязковий kwarg заважає, тихо допише `= nil`.
    it "refuses to render without the total — a silent default would read as full coverage" do
      expect {
        component_class.new(trees: trees, organization: Organization.new(id: 42, stream_epoch: 7))
      }.to raise_error(ArgumentError, /map_total/)
    end
  end
end

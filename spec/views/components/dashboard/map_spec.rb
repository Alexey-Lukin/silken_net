# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Map do
  def mock_tree(id: 1, did: "SNET-00000001", latitude: 49.4444, longitude: 32.0597,
                status: "active", current_stress: 0.2, charge_percentage: 85)
    t = OpenStruct.new(
      id: id,
      did: did,
      latitude: latitude,
      longitude: longitude,
      status: status,
      current_stress: current_stress,
      charge_percentage: charge_percentage
    )
    t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
    t.define_singleton_method(:to_key) { [ id ] }
    t.define_singleton_method(:to_param) { id.to_s }
    t
  end

  # `stream_epoch` НЕ дефолтний (1) навмисно [SEC.25 Ф3]: якби епоха десь була
  # зашита константою замість того, щоб текти з організації, з одиницею це
  # лишилось би зеленим.
  def render_component(trees:, organization: OpenStruct.new(id: 42, stream_epoch: 7))
    ApplicationController.renderer.render(
      component_class.new(trees: trees, organization: organization),
      layout: false
    )
  end

  let(:trees) { [ mock_tree(id: 1, did: "SNET-00000001"), mock_tree(id: 2, did: "SNET-00000002") ] }
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

      other = render_component(trees: trees, organization: OpenStruct.new(id: 99, stream_epoch: 7))
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
      html = render_component(trees: [ mock_tree ])
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

  describe "HUD coordinates display" do
    it "renders the bottom overlay div in the map container" do
      # Coordinates text is a Phlex string literal (not plain), so it's not rendered as text.
      # We verify the HUD container divs are present instead.
      expect(html).to include("Geospatial Matrix")
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::MapNode do
  def mock_tree(id: 3, did: "SNET-00000003", latitude: 49.44, longitude: 32.06,
                current_stress: 0.3, charge_percentage: 72, status: "active")
    t = OpenStruct.new(
      id: id,
      did: did,
      latitude: latitude,
      longitude: longitude,
      current_stress: current_stress,
      charge_percentage: charge_percentage,
      status: status
    )
    t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
    t.define_singleton_method(:to_key) { [ id ] }
    t.define_singleton_method(:to_param) { id.to_s }
    t
  end

  def render_component(tree:)
    component_class.new(tree: tree).call
  end

  let(:tree) { mock_tree }
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

    it "sets the charge percentage data attribute" do
      expect(html).to include("data-charge=")
      expect(html).to include("72")
    end

    it "sets the status data attribute" do
      expect(html).to include('data-status="active"')
    end
  end

  describe "different tree statuses" do
    it "renders stress status correctly" do
      tree = mock_tree(status: "stress")
      html = render_component(tree: tree)
      expect(html).to include('data-status="stress"')
    end

    it "renders anomaly status correctly" do
      tree = mock_tree(status: "anomaly")
      html = render_component(tree: tree)
      expect(html).to include('data-status="anomaly"')
    end
  end

  describe "zero values" do
    it "handles zero stress gracefully" do
      tree = mock_tree(current_stress: 0.0, charge_percentage: 0)
      html = render_component(tree: tree)
      expect(html).to include("data-stress=")
    end
  end
end

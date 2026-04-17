# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Grid do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_pagy
    pagy = OpenStruct.new(count: 63, page: 1, last: 3, from: 1, to: 21, prev: nil, next: 2, vars: { items: 21 })
    pagy.define_singleton_method(:series) { [1, 2, 3] }
    pagy
  end

  def mock_cluster(id: 1, name: "Carpathian-Alpha", active_threats: false, total_active_trees: 42,
                   health_index: 0.85)
    cluster = OpenStruct.new(
      id: id,
      name: name,
      total_active_trees: total_active_trees,
      health_index: health_index
    )
    cluster.define_singleton_method(:active_threats?) { active_threats }
    cluster.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    cluster.define_singleton_method(:to_key) { [id] }
    cluster.define_singleton_method(:to_param) { id.to_s }
    cluster
  end

  let(:clusters) { [mock_cluster(id: 1, name: "Carpathian-Alpha"), mock_cluster(id: 2, name: "Danube-Beta")] }
  let(:html)     { render_component(clusters: clusters, pagy: mock_pagy) }

  describe "grid layout" do
    it "renders a grid container" do
      expect(html).to include("grid")
    end

    it "renders each cluster item" do
      expect(html).to include("Carpathian-Alpha")
      expect(html).to include("Danube-Beta")
    end
  end

  describe "item delegation" do
    it "renders cluster ID" do
      expect(html).to include("ID: 1")
    end

    it "renders Open Matrix link" do
      expect(html).to include("Open Matrix")
    end

    it "renders health index as percentage" do
      expect(html).to include("85%")
    end

    it "renders tree count" do
      expect(html).to include("42")
    end
  end

  describe "LED status" do
    it "renders emerald LED when no active threats" do
      expect(html).to include("bg-emerald-500")
    end

    it "renders red LED when cluster has active threats" do
      threat_cluster = mock_cluster(id: 3, name: "Threat-Cluster", active_threats: true)
      html = render_component(clusters: [threat_cluster], pagy: mock_pagy)
      expect(html).to include("bg-red-500")
    end
  end

  describe "empty state" do
    it "renders empty state message when no clusters" do
      html = render_component(clusters: [], pagy: mock_pagy)
      expect(html).to include("Matrix is empty")
    end
  end

  describe "pagination" do
    it "renders pagination links" do
      expect(html).to include("page=")
    end
  end
end

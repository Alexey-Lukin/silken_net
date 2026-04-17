# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Item do
  def mock_cluster(id: 1, name: "Carpathian-Alpha", active_threats: false,
                   total_active_trees: 42, health_index: 0.91)
    cluster = OpenStruct.new(
      id: id,
      name: name,
      total_active_trees: total_active_trees,
      health_index: health_index
    )
    cluster.define_singleton_method(:active_threats?) { active_threats }
    cluster.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    cluster.define_singleton_method(:to_key) { [ id ] }
    cluster.define_singleton_method(:to_param) { id.to_s }
    cluster
  end

  let(:cluster) { mock_cluster }
  let(:html)    { render_component(cluster: cluster) }

  describe "header section" do
    it "renders cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders cluster ID" do
      expect(html).to include("ID: 1")
    end
  end

  describe "LED status indicator" do
    it "renders emerald LED when no active threats" do
      expect(html).to include("bg-emerald-500")
    end

    it "does not render red LED when no active threats" do
      expect(html).not_to include("bg-red-500")
    end

    it "renders red pulsing LED when cluster has active threats" do
      threat_cluster = mock_cluster(id: 2, name: "Threat-Node", active_threats: true)
      html = render_component(cluster: threat_cluster)
      expect(html).to include("bg-red-500")
    end

    it "does not render emerald LED when threats are active" do
      threat_cluster = mock_cluster(id: 2, active_threats: true)
      html = render_component(cluster: threat_cluster)
      expect(html).not_to include("bg-emerald-500")
    end
  end

  describe "stats section" do
    it "renders Trees label" do
      expect(html).to include("Trees")
    end

    it "renders tree count" do
      expect(html).to include("42")
    end

    it "renders Health label" do
      expect(html).to include("Health")
    end

    it "renders health index as percentage" do
      expect(html).to include("91%")
    end
  end

  describe "footer link" do
    it "renders Open Matrix link" do
      expect(html).to include("Open Matrix")
    end

    it "links to the cluster path" do
      expect(html).to include("/api/v1/clusters/1")
    end
  end
end

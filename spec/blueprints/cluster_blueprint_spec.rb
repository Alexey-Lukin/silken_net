# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterBlueprint, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:cluster) { create(:cluster, name: "Korsun Forest", region: "Cherkasy Oblast") }

  describe "default view" do
    subject(:parsed) { JSON.parse(described_class.render(cluster)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(cluster.id)
    end

    it "includes name and region" do
      expect(parsed["name"]).to eq("Korsun Forest")
      expect(parsed["region"]).to eq("Cherkasy Oblast")
    end

    it "includes computed health_index" do
      expect(parsed["health_index"]).to be_a(Numeric)
    end

    it "includes computed total_active_trees" do
      expect(parsed["total_active_trees"]).to be_a(Integer)
    end

    it "includes computed geo_center" do
      expect(parsed).to have_key("geo_center")
    end

    it "includes computed active_threats" do
      expect(parsed["active_threats"]).to be_in([ true, false ])
    end
  end

  describe "health_index defaults to 1.0 when unset" do
    it "returns 1.0 for a fresh cluster" do
      parsed = JSON.parse(described_class.render(cluster))
      expect(parsed["health_index"]).to eq(1.0)
    end
  end

  describe "total_active_trees reflects denormalized counter" do
    it "returns 0 for a cluster with no trees" do
      parsed = JSON.parse(described_class.render(cluster))
      expect(parsed["total_active_trees"]).to eq(0)
    end
  end

  describe "active_threats without alerts" do
    it "returns false when no critical alerts exist" do
      parsed = JSON.parse(described_class.render(cluster))
      expect(parsed["active_threats"]).to be false
    end
  end

  describe "collection rendering" do
    let!(:clusters) { create_list(:cluster, 3) }

    it "renders an array of clusters" do
      parsed = JSON.parse(described_class.render(clusters))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      parsed.each do |c|
        expect(c).to have_key("name")
        expect(c).to have_key("health_index")
      end
    end
  end
end

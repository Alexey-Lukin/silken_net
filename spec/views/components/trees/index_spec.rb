# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Index do
  let(:cluster) { mock_cluster }
  let(:trees) { [ mock_tree ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(cluster: cluster, trees: trees, pagy: pagy) }


  def mock_cluster(id: 1, name: "Carpathian-Alpha", active_trees_count: 5)
    c = OpenStruct.new(id: id, name: name, active_trees_count: active_trees_count)
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  def mock_tree(did: "SNET-00000042", status: "active", ionic_voltage: 3800,
                charge_percentage: 85, last_seen_at: 1.minute.ago, under_threat: false)
    t = OpenStruct.new(
      did: did,
      status: status,
      ionic_voltage: ionic_voltage,
      charge_percentage: charge_percentage,
      last_seen_at: last_seen_at
    )
    t.define_singleton_method(:under_threat?) { under_threat }
    t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
    t.define_singleton_method(:to_key) { [ 1 ] }
    t.define_singleton_method(:to_param) { "1" }
    t
  end

  describe "header" do
    it "displays sector matrix deployment title" do
      expect(html).to include("Sector Matrix Deployment")
    end

    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays population count" do
      expect(html).to include("Soldiers")
    end

    it "displays operational nodes count" do
      expect(html).to include("5")
      expect(html).to include("Nodes")
    end
  end

  describe "soldier node grid" do
    it "renders last 6 chars of DID" do
      expect(html).to include("000042")
    end

    it "displays tree status" do
      expect(html).to include("active")
    end

    it "displays voltage" do
      expect(html).to include("3800")
      expect(html).to include("mV")
    end
  end

  describe "LED indicator" do
    it "shows emerald LED for active, recently seen tree" do
      expect(html).to include("bg-emerald-500")
    end

    it "shows red pulsing LED when under threat" do
      trees = [ mock_tree(under_threat: true) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-red-600")
      expect(rendered).to include("animate-pulse")
    end

    it "shows gray LED when silent for over 24 hours" do
      trees = [ mock_tree(last_seen_at: 25.hours.ago) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-gray-800")
    end

    it "shows gray LED when last_seen_at is nil" do
      trees = [ mock_tree(last_seen_at: nil) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-gray-800")
    end
  end

  describe "status text colors" do
    it "renders active status with emerald text" do
      expect(html).to include("text-emerald-700")
    end

    it "renders dormant status with gray text" do
      trees = [ mock_tree(status: "dormant") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("text-gray-600")
    end

    it "renders removed status with red text" do
      trees = [ mock_tree(status: "removed") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("text-red-800")
    end

    it "renders deceased status with red text" do
      trees = [ mock_tree(status: "deceased") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("text-red-800")
    end
  end

  describe "charge bar colors" do
    it "shows emerald bar when charge > 70%" do
      expect(html).to include("bg-emerald-500")
    end

    it "shows warning bar when charge between 30-70%" do
      trees = [ mock_tree(charge_percentage: 50) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
    end

    it "shows red pulsing bar when charge < 30%" do
      trees = [ mock_tree(charge_percentage: 20) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-red-600")
      expect(rendered).to include("animate-pulse")
    end
  end

  describe "pagination" do
    it "renders without errors with pagy" do
      expect(html).to be_present
    end

    it "renders without pagination when pagy is nil" do
      rendered = render_component(cluster: cluster, trees: trees, pagy: nil)
      expect(rendered).to include("Sector Matrix Deployment")
    end
  end

  describe "multiple trees" do
    it "renders all tree nodes" do
      trees = [
        mock_tree(did: "SNET-00000001"),
        mock_tree(did: "SNET-00000002")
      ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("000001")
      expect(rendered).to include("000002")
    end
  end

  describe "empty grid" do
    it "renders without errors when no trees" do
      rendered = render_component(cluster: cluster, trees: [], pagy: mock_pagy(count: 0, last: 1))
      expect(rendered).to include("Sector Matrix Deployment")
    end
  end
end

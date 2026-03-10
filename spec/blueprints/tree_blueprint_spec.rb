# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeBlueprint, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:tree_family) { create(:tree_family, name: "Quercus robur", baseline_impedance: 1500) }
  let(:cluster) { create(:cluster) }
  let(:tree) do
    create(:tree, tree_family: tree_family, cluster: cluster,
                  status: :active, latitude: 50.4501, longitude: 30.5234)
  end
  let(:wallet) { tree.wallet }

  describe ":minimal view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :minimal)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(tree.id)
    end

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "excludes fields from other views" do
      expect(parsed).not_to have_key("latitude")
      expect(parsed).not_to have_key("longitude")
      expect(parsed).not_to have_key("current_stress")
      expect(parsed).not_to have_key("wallet")
    end
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :index)) }

    it "includes location fields" do
      expect(parsed["latitude"]).to be_a(Numeric)
      expect(parsed["longitude"]).to be_a(Numeric)
    end

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "includes computed current_stress" do
      expect(parsed).to have_key("current_stress")
    end

    it "includes computed under_threat?" do
      expect(parsed).to have_key("under_threat?")
      expect(parsed["under_threat?"]).to be_in([ true, false ])
    end

    it "includes nested wallet" do
      wallet_data = parsed["wallet"]
      expect(wallet_data).to be_a(Hash)
      expect(wallet_data["id"]).to eq(wallet.id)
      expect(wallet_data["balance"]).to be_a(Numeric)
    end

    it "includes tree_family_name" do
      expect(parsed["tree_family_name"]).to eq("Quercus robur")
    end

    it "excludes show-only fields" do
      expect(parsed).not_to have_key("baseline_impedance")
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :show)) }

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "includes computed current_stress" do
      expect(parsed).to have_key("current_stress")
    end

    it "includes computed under_threat?" do
      expect(parsed).to have_key("under_threat?")
    end

    it "includes nested wallet" do
      wallet_data = parsed["wallet"]
      expect(wallet_data).to be_a(Hash)
      expect(wallet_data["id"]).to eq(wallet.id)
    end

    it "includes tree_family_name" do
      expect(parsed["tree_family_name"]).to eq("Quercus robur")
    end

    it "includes baseline_impedance from tree_family" do
      expect(parsed["baseline_impedance"]).to eq(1500)
    end
  end

  describe "nil tree_family edge case" do
    let(:tree) { create(:tree, tree_family: nil, cluster: cluster) }

    it "returns nil for tree_family_name in :index" do
      parsed = JSON.parse(described_class.render(tree, view: :index))
      expect(parsed["tree_family_name"]).to be_nil
    end

    it "returns nil for baseline_impedance in :show" do
      parsed = JSON.parse(described_class.render(tree, view: :show))
      expect(parsed["baseline_impedance"]).to be_nil
    end
  end

  describe "collection rendering" do
    let!(:trees) { create_list(:tree, 3, tree_family: tree_family, cluster: cluster) }

    it "renders an array of trees" do
      parsed = JSON.parse(described_class.render(trees, view: :minimal))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed.map { |t| t["did"] }).to all(start_with("SNET-"))
    end
  end
end

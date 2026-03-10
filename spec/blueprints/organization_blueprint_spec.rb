# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationBlueprint, type: :model do
  let(:organization) do
    create(:organization, name: "EcoForest UA",
                          billing_email: "billing@ecoforest.ua",
                          crypto_public_address: "0x" + "ab" * 20,
                          data_region: "eu-west")
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(organization, view: :index)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(organization.id)
    end

    it "includes name and crypto_public_address" do
      expect(parsed["name"]).to eq("EcoForest UA")
      expect(parsed["crypto_public_address"]).to eq("0x" + "ab" * 20)
    end

    it "includes created_at" do
      expect(parsed).to have_key("created_at")
    end

    it "includes computed total_clusters" do
      expect(parsed["total_clusters"]).to eq(0)
    end

    it "includes computed total_invested" do
      expect(parsed["total_invested"]).to eq(0.0)
    end

    it "excludes show-only fields" do
      expect(parsed).not_to have_key("billing_email")
      expect(parsed).not_to have_key("data_region")
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(organization, view: :show)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(organization.id)
    end

    it "includes all detail fields" do
      expect(parsed["name"]).to eq("EcoForest UA")
      expect(parsed["crypto_public_address"]).to eq("0x" + "ab" * 20)
      expect(parsed["billing_email"]).to eq("billing@ecoforest.ua")
      expect(parsed["data_region"]).to eq("eu-west")
    end

    it "includes created_at" do
      expect(parsed).to have_key("created_at")
    end

    it "excludes computed index fields" do
      expect(parsed).not_to have_key("total_clusters")
      expect(parsed).not_to have_key("total_invested")
    end
  end

  describe "total_clusters reflects actual cluster count" do
    before do
      create_list(:cluster, 2, organization: organization)
    end

    it "returns the count of clusters" do
      parsed = JSON.parse(described_class.render(organization, view: :index))
      expect(parsed["total_clusters"]).to eq(2)
    end
  end

  describe "collection rendering" do
    let!(:organizations) { create_list(:organization, 3) }

    it "renders an array of organizations" do
      parsed = JSON.parse(described_class.render(organizations, view: :index))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
    end
  end
end

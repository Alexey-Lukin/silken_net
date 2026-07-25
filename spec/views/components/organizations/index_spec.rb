# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::Index do
  def mock_org(id: 1, name: "EcoInvest DAO", total_clusters: 5, total_invested: 12_000,
               crypto_public_address: "0xAbCd1234AbCd1234AbCd1234AbCd1234AbCd1234")
    org = OpenStruct.new(
      id: id,
      name: name,
      total_clusters: total_clusters,
      total_invested: total_invested,
      crypto_public_address: crypto_public_address
    )
    org.define_singleton_method(:model_name) { ActiveModel::Name.new(Organization) }
    org.define_singleton_method(:to_key) { [ id ] }
    org.define_singleton_method(:to_param) { id.to_s }
    org
  end

  let(:org)           { mock_org }
  let(:organizations) { [ org, mock_org(id: 2, name: "GreenFund Ltd", total_invested: 5_000) ] }
  let(:html)          { render_component(organizations: organizations, pagy: mock_pagy(count: 63)) }

  describe "header section" do
    it "renders the Global Clan Registry heading" do
      expect(html).to include("Global Clan Registry")
    end

    it "renders the subtitle" do
      expect(html).to include("multi-tenant entities")
    end
  end

  describe "table headers" do
    it "renders Organization Name column" do
      expect(html).to include("Organization Name")
    end

    it "renders Contracted column" do
      expect(html).to include("Contracted")
    end

    it "renders On-Chain Identity column" do
      expect(html).to include("On-Chain Identity")
    end

    it "renders Audit column" do
      expect(html).to include("Audit")
    end
  end

  describe "organization rows" do
    it "renders organization name" do
      expect(html).to include("EcoInvest DAO")
    end

    it "renders total invested with SCC suffix" do
      expect(html).to include("12000 SCC")
    end

    it "renders cluster count" do
      expect(html).to include("5")
    end

    it "renders VIEW_PROFILE link" do
      expect(html).to include("VIEW_PROFILE")
    end

    it "renders link with aria-label for org name" do
      expect(html).to include("View EcoInvest DAO profile")
    end

    it "renders second organization name" do
      expect(html).to include("GreenFund Ltd")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end
  end
end

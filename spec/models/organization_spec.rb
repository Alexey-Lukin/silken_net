# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "associations" do
    it "has gateways through clusters" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      gateway = create(:gateway, cluster: cluster)

      expect(organization.gateways).to include(gateway)
    end

    it "has wallets directly via organization_id (denormalized)" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster)
      wallet = tree.wallet

      expect(wallet.organization).to eq(organization)
      expect(organization.wallets).to include(wallet)
    end

    it "has audit_logs with delete_all dependency strategy" do
      reflection = Organization.reflect_on_association(:audit_logs)
      expect(reflection.options[:dependent]).to eq(:delete_all)
    end
  end

  describe "#total_carbon_points" do
    it "sums wallet balances via direct association" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree1 = create(:tree, cluster: cluster)
      tree2 = create(:tree, cluster: cluster)

      tree1.wallet.update!(balance: 100)
      tree2.wallet.update!(balance: 250)

      expect(organization.total_carbon_points).to eq(350)
    end
  end

  describe "#health_score" do
    it "returns 1.0 when organization has no clusters" do
      organization = create(:organization)
      expect(organization.health_score).to eq(1.0)
    end

    it "calculates average of denormalized health_index" do
      organization = create(:organization)
      create(:cluster, organization: organization, health_index: 0.8)
      create(:cluster, organization: organization, health_index: 0.6)

      expect(organization.health_score).to eq(0.7)
    end
  end
end

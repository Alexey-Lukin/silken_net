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

  describe "#total_clusters" do
    it "returns the count of clusters" do
      organization = create(:organization)
      create_list(:cluster, 3, organization: organization)

      expect(organization.total_clusters).to eq(3)
    end

    it "returns 0 when organization has no clusters" do
      organization = create(:organization)
      expect(organization.total_clusters).to eq(0)
    end
  end

  describe "#total_invested" do
    it "returns the sum of all contract funding" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 30_000)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 20_000)

      expect(organization.total_invested).to eq(50_000.0)
    end

    it "returns 0.0 when no contracts exist" do
      organization = create(:organization)
      expect(organization.total_invested).to eq(0.0)
    end
  end

  describe "#under_threat?" do
    it "returns true when organization has unresolved critical alerts" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      create(:ews_alert, cluster: cluster, severity: :critical, status: :active, alert_type: :fire_detected)

      expect(organization).to be_under_threat
    end

    it "returns false when no critical alerts exist" do
      organization = create(:organization)
      expect(organization).not_to be_under_threat
    end
  end

  describe "validations" do
    it "requires name" do
      org = build(:organization, name: nil)
      expect(org).not_to be_valid
    end

    it "requires unique name" do
      create(:organization, name: "Unique Org")
      duplicate = build(:organization, name: "Unique Org")
      expect(duplicate).not_to be_valid
    end

    it "requires billing_email" do
      org = build(:organization, billing_email: nil)
      expect(org).not_to be_valid
    end

    it "validates billing_email format" do
      org = build(:organization, billing_email: "not-an-email")
      expect(org).not_to be_valid
    end

    it "requires crypto_public_address" do
      org = build(:organization, crypto_public_address: nil)
      expect(org).not_to be_valid
    end

    it "validates crypto_public_address format" do
      org = build(:organization, crypto_public_address: "not-a-wallet")
      expect(org).not_to be_valid
    end

    it "accepts valid Ethereum address with mixed case (EIP-55)" do
      org = build(:organization, crypto_public_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B")
      expect(org).to be_valid
    end
  end
end

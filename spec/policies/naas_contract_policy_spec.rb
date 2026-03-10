# frozen_string_literal: true

require "rails_helper"

RSpec.describe NaasContractPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_org) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }

  describe "#show?" do
    it "allows user from same org" do
      contract = create(:naas_contract, organization: organization, cluster: cluster)
      expect(described_class.new(investor, contract).show?).to be true
    end

    it "denies user from different org" do
      contract = create(:naas_contract, organization: other_org, cluster: other_cluster)
      expect(described_class.new(investor, contract).show?).to be false
    end

    it "allows admin regardless of org" do
      contract = create(:naas_contract, organization: other_org, cluster: other_cluster)
      expect(described_class.new(admin, contract).show?).to be true
    end
  end

  describe "Scope" do
    let!(:own_contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let!(:other_contract) { create(:naas_contract, organization: other_org, cluster: other_cluster) }

    it "scopes to org contracts for investor" do
      scope = described_class::Scope.new(investor, NaasContract).resolve
      expect(scope).to include(own_contract)
      expect(scope).not_to include(other_contract)
    end

    it "returns all for admin" do
      scope = described_class::Scope.new(admin, NaasContract).resolve
      expect(scope).to include(own_contract, other_contract)
    end
  end

  describe "#index?" do
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:super_admin_idx) { create(:user, :super_admin) }

    it "returns true for all users" do
      expect(described_class.new(investor, contract).index?).to be true
      expect(described_class.new(forester, contract).index?).to be true
      expect(described_class.new(super_admin_idx, contract).index?).to be true
    end
  end

  describe "#stats?" do
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:super_admin_stats) { create(:user, :super_admin) }

    it "returns true for all users" do
      expect(described_class.new(investor, contract).stats?).to be true
      expect(described_class.new(forester, contract).stats?).to be true
      expect(described_class.new(admin, contract).stats?).to be true
      expect(described_class.new(super_admin_stats, contract).stats?).to be true
    end
  end
end

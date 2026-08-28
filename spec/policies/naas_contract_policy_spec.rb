# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe NaasContractPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_org) }

  let(:subscriber) { create(:user, :subscriber, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "#show?" do
    it "allows user from same org" do
      contract = create(:naas_contract, organization: organization, cluster: cluster)
      expect(described_class.new(subscriber, contract).show?).to be true
    end

    it "denies user from different org" do
      contract = create(:naas_contract, organization: other_org, cluster: other_cluster)
      expect(described_class.new(subscriber, contract).show?).to be false
    end

    it "denies admin from a different org (admin is org-scoped, not platform)" do
      contract = create(:naas_contract, organization: other_org, cluster: other_cluster)
      expect(described_class.new(admin, contract).show?).to be false
    end

    # [SEC.25 Ф2] «regardless of org» більше не діє: фінанси NaaS бачить лише
    # acting-організація, і для super_admin теж.
    it "дозволяє super_admin лише в контексті організації-власника" do
      contract = create(:naas_contract, organization: other_org, cluster: other_cluster)

      expect(described_class.new(UserContext.new(super_admin, other_org), contract).show?).to be true
      expect(described_class.new(UserContext.new(super_admin, organization), contract).show?).to be false
    end
  end

  describe "Scope" do
    let!(:own_contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let!(:other_contract) { create(:naas_contract, organization: other_org, cluster: other_cluster) }

    it "scopes to org contracts for subscriber" do
      scope = described_class::Scope.new(subscriber, NaasContract).resolve
      expect(scope).to include(own_contract)
      expect(scope).not_to include(other_contract)
    end

    it "звужує super_admin до acting-організації, і перемикання її змінює" do
      in_own = described_class::Scope.new(UserContext.new(super_admin, organization), NaasContract).resolve
      in_other = described_class::Scope.new(UserContext.new(super_admin, other_org), NaasContract).resolve

      expect(in_own).to contain_exactly(own_contract)
      expect(in_other).to contain_exactly(other_contract)
    end

    it "scopes admin to own org (org-scoped, not platform)" do
      scope = described_class::Scope.new(admin, NaasContract).resolve
      expect(scope).to include(own_contract)
      expect(scope).not_to include(other_contract)
    end
  end

  describe "#index?" do
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:super_admin_idx) { create(:user, :super_admin) }

    it "returns true for all users" do
      expect(described_class.new(subscriber, contract).index?).to be true
      expect(described_class.new(forester, contract).index?).to be true
      expect(described_class.new(super_admin_idx, contract).index?).to be true
    end
  end

  describe "#stats?" do
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:super_admin_stats) { create(:user, :super_admin) }

    it "returns true for all users" do
      expect(described_class.new(subscriber, contract).stats?).to be true
      expect(described_class.new(forester, contract).stats?).to be true
      expect(described_class.new(admin, contract).stats?).to be true
      expect(described_class.new(super_admin_stats, contract).stats?).to be true
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Policy coverage — uncovered branches and lines" do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_org) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
  end

  # ==========================================================================
  # 1. APPLICATION POLICY — Lines 16, 24, 28, 58
  # ==========================================================================
  describe ApplicationPolicy do
    let(:record) { double("Record") }

    describe "#show?" do
      it "returns true for investor" do
        expect(described_class.new(investor, record).show?).to be true
      end

      it "returns true for forester" do
        expect(described_class.new(forester, record).show?).to be true
      end

      it "returns true for admin" do
        expect(described_class.new(admin, record).show?).to be true
      end

      it "returns true for super_admin" do
        expect(described_class.new(super_admin, record).show?).to be true
      end
    end

    describe "#update?" do
      it "denies investors" do
        expect(described_class.new(investor, record).update?).to be false
      end

      it "denies foresters" do
        expect(described_class.new(forester, record).update?).to be false
      end

      it "allows admins" do
        expect(described_class.new(admin, record).update?).to be true
      end

      it "allows super_admins" do
        expect(described_class.new(super_admin, record).update?).to be true
      end
    end

    describe "#destroy?" do
      it "denies investors" do
        expect(described_class.new(investor, record).destroy?).to be false
      end

      it "denies foresters" do
        expect(described_class.new(forester, record).destroy?).to be false
      end

      it "allows admins" do
        expect(described_class.new(admin, record).destroy?).to be true
      end

      it "allows super_admins" do
        expect(described_class.new(super_admin, record).destroy?).to be true
      end
    end

    describe "Scope#resolve" do
      it "returns scope.all for any user" do
        scope = described_class::Scope.new(investor, Tree).resolve
        expect(scope).to be_a(ActiveRecord::Relation)
      end

      it "returns scope.all for super_admin" do
        scope = described_class::Scope.new(super_admin, Tree).resolve
        expect(scope).to be_a(ActiveRecord::Relation)
      end
    end
  end

  # ==========================================================================
  # 2. ACTUATOR POLICY — Lines 9, 18-21
  # ==========================================================================
  describe ActuatorPolicy do
    let(:gateway) { create(:gateway, cluster: cluster) }
    let(:actuator) { create(:actuator, gateway: gateway) }

    describe "#show?" do
      it "allows forester" do
        expect(described_class.new(forester, actuator).show?).to be true
      end

      it "denies investor" do
        expect(described_class.new(investor, actuator).show?).to be false
      end

      it "allows admin" do
        expect(described_class.new(admin, actuator).show?).to be true
      end

      it "allows super_admin" do
        expect(described_class.new(super_admin, actuator).show?).to be true
      end
    end

    describe "Scope#resolve" do
      let!(:own_actuator) { create(:actuator, gateway: gateway) }
      let(:other_gateway) { create(:gateway, cluster: other_cluster) }
      let!(:other_actuator) { create(:actuator, gateway: other_gateway) }

      it "returns all actuators for super_admin" do
        scope = described_class::Scope.new(super_admin, Actuator).resolve
        expect(scope).to include(own_actuator)
        expect(scope).to include(other_actuator)
      end

      it "scopes to org actuators for non-super_admin" do
        scope = described_class::Scope.new(investor, Actuator).resolve
        expect(scope).to include(own_actuator)
        expect(scope).not_to include(other_actuator)
      end

      it "scopes to org actuators for forester" do
        scope = described_class::Scope.new(forester, Actuator).resolve
        expect(scope).to include(own_actuator)
        expect(scope).not_to include(other_actuator)
      end
    end
  end

  # ==========================================================================
  # 3. ORGANIZATION POLICY — Lines 14-17
  # ==========================================================================
  describe OrganizationPolicy do
    describe "Scope#resolve" do
      let!(:org1) { organization }
      let!(:org2) { other_org }

      it "returns all orgs for super_admin" do
        scope = described_class::Scope.new(super_admin, Organization).resolve
        expect(scope).to include(org1, org2)
      end

      it "scopes to own org for non-super_admin" do
        scope = described_class::Scope.new(investor, Organization).resolve
        expect(scope).to include(org1)
        expect(scope).not_to include(org2)
      end

      it "scopes to own org for admin" do
        scope = described_class::Scope.new(admin, Organization).resolve
        expect(scope).to include(org1)
        expect(scope).not_to include(org2)
      end
    end
  end

  # ==========================================================================
  # 4. EWS ALERT POLICY — Lines 5, 15
  # ==========================================================================
  describe EwsAlertPolicy do
    let!(:own_alert) { create(:ews_alert, cluster: cluster) }
    let!(:other_alert) { create(:ews_alert, cluster: other_cluster) }

    describe "#index?" do
      it "returns true for all users" do
        expect(described_class.new(investor, own_alert).index?).to be true
        expect(described_class.new(forester, own_alert).index?).to be true
        expect(described_class.new(admin, own_alert).index?).to be true
        expect(described_class.new(super_admin, own_alert).index?).to be true
      end
    end

    describe "Scope#resolve" do
      it "returns all alerts for super_admin" do
        scope = described_class::Scope.new(super_admin, EwsAlert).resolve
        expect(scope).to include(own_alert, other_alert)
      end

      it "scopes to org alerts for non-super_admin" do
        scope = described_class::Scope.new(investor, EwsAlert).resolve
        expect(scope).to include(own_alert)
        expect(scope).not_to include(other_alert)
      end
    end
  end

  # ==========================================================================
  # 5. NAAS CONTRACT POLICY — Lines 5, 13
  # ==========================================================================
  describe NaasContractPolicy do
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    describe "#index?" do
      it "returns true for all users" do
        expect(described_class.new(investor, contract).index?).to be true
        expect(described_class.new(forester, contract).index?).to be true
        expect(described_class.new(super_admin, contract).index?).to be true
      end
    end

    describe "#stats?" do
      it "returns true for all users" do
        expect(described_class.new(investor, contract).stats?).to be true
        expect(described_class.new(forester, contract).stats?).to be true
        expect(described_class.new(admin, contract).stats?).to be true
        expect(described_class.new(super_admin, contract).stats?).to be true
      end
    end
  end

  # ==========================================================================
  # 6. TREE POLICY — Lines 5, 9
  # ==========================================================================
  describe TreePolicy do
    let(:tree) { create(:tree, cluster: cluster) }

    describe "#index?" do
      it "returns true for all users" do
        expect(described_class.new(investor, tree).index?).to be true
        expect(described_class.new(forester, tree).index?).to be true
        expect(described_class.new(admin, tree).index?).to be true
        expect(described_class.new(super_admin, tree).index?).to be true
      end
    end

    describe "#show?" do
      it "returns true for all users" do
        expect(described_class.new(investor, tree).show?).to be true
        expect(described_class.new(forester, tree).show?).to be true
        expect(described_class.new(admin, tree).show?).to be true
        expect(described_class.new(super_admin, tree).show?).to be true
      end
    end
  end

  # ==========================================================================
  # 7. WALLET POLICY — Line 5, branch on line 11
  # ==========================================================================
  describe WalletPolicy do
    describe "#index?" do
      let(:tree) { create(:tree, cluster: cluster) }
      let(:wallet) { tree.wallet }

      it "returns true for all users" do
        expect(described_class.new(investor, wallet).index?).to be true
        expect(described_class.new(forester, wallet).index?).to be true
        expect(described_class.new(admin, wallet).index?).to be true
        expect(described_class.new(super_admin, wallet).index?).to be true
      end
    end

    describe "#show? when tree.cluster.organization_id is nil" do
      it "denies access when wallet has no org chain and user is not admin" do
        # Create a tree with a cluster, then stub the chain to simulate nil organization_id and cluster
        tree = create(:tree, cluster: cluster)
        wallet = tree.wallet

        # Stub the tree's cluster chain to return nil for organization_id
        allow(wallet).to receive(:organization_id).and_return(nil)
        allow(wallet).to receive(:tree).and_return(double(cluster: nil))

        other_user = create(:user, :investor, organization: other_org)
        expect(described_class.new(other_user, wallet).show?).to be false
      end

      it "denies when tree has no cluster" do
        tree = create(:tree, cluster: cluster)
        wallet = tree.wallet

        allow(wallet).to receive(:organization_id).and_return(nil)
        tree_double = double(cluster: nil)
        allow(wallet).to receive(:tree).and_return(tree_double)

        expect(described_class.new(investor, wallet).show?).to be false
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
  end

  describe "#show?" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    it "allows admin" do
      expect(described_class.new(admin, wallet).show?).to be true
    end

    it "allows user from same org" do
      expect(described_class.new(investor, wallet).show?).to be true
    end

    context "when wallet belongs to another org" do
      let(:other_cluster) { create(:cluster, organization: other_org) }
      let(:other_tree) { create(:tree, cluster: other_cluster) }
      let(:other_wallet) { other_tree.wallet }

      it "denies user from different org" do
        expect(described_class.new(investor, other_wallet).show?).to be false
      end

      it "allows super_admin" do
        expect(described_class.new(super_admin, other_wallet).show?).to be true
      end
    end
  end

  describe "Scope" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_tree) { create(:tree, cluster: cluster) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    it "scopes to org wallets for regular user" do
      scope = described_class::Scope.new(investor, Wallet).resolve
      expect(scope).to include(own_tree.wallet)
      expect(scope).not_to include(other_tree.wallet)
    end

    it "returns all for admin" do
      scope = described_class::Scope.new(admin, Wallet).resolve
      expect(scope).to include(own_tree.wallet, other_tree.wallet)
    end
  end

  describe "#index?" do
    let(:forester) { create(:user, :forester, organization: organization) }

    it "returns true for all users" do
      expect(described_class.new(investor, wallet).index?).to be true
      expect(described_class.new(forester, wallet).index?).to be true
      expect(described_class.new(admin, wallet).index?).to be true
      expect(described_class.new(super_admin, wallet).index?).to be true
    end
  end

  describe "#show? when tree.cluster.organization_id is nil" do
    it "denies access when wallet has no org chain and user is not admin" do
      allow(wallet).to receive(:organization_id).and_return(nil)
      allow(wallet).to receive(:tree).and_return(double(cluster: nil))

      other_user = create(:user, :investor, organization: other_org)
      expect(described_class.new(other_user, wallet).show?).to be false
    end

    it "denies when tree has no cluster" do
      allow(wallet).to receive(:organization_id).and_return(nil)
      tree_double = double(cluster: nil)
      allow(wallet).to receive(:tree).and_return(tree_double)

      expect(described_class.new(investor, wallet).show?).to be false
    end
  end
end

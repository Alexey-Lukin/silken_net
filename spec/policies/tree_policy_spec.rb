# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreePolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_org) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
  end

  describe "Scope" do
    let!(:own_tree) { create(:tree, cluster: cluster) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }
    let!(:clusterless_tree) { create(:tree, cluster: nil) }

    it "includes org trees for regular user" do
      scope = described_class::Scope.new(investor, Tree).resolve
      expect(scope).to include(own_tree)
      expect(scope).not_to include(other_tree)
    end

    it "includes clusterless trees for regular user" do
      scope = described_class::Scope.new(investor, Tree).resolve
      expect(scope).to include(clusterless_tree)
    end

    it "returns all trees for super_admin" do
      scope = described_class::Scope.new(super_admin, Tree).resolve
      expect(scope).to include(own_tree, other_tree, clusterless_tree)
    end
  end
end

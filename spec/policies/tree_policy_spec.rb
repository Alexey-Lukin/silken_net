# SPDX-License-Identifier: AGPL-3.0-or-later
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

    it "звужує super_admin до acting-організації, і перемикання її змінює" do
      in_own = described_class::Scope.new(UserContext.new(super_admin, organization), Tree).resolve
      in_other = described_class::Scope.new(UserContext.new(super_admin, other_org), Tree).resolve

      expect(in_own).to include(own_tree)
      expect(in_own).not_to include(other_tree)
      expect(in_other).to include(other_tree)
      expect(in_other).not_to include(own_tree)
      # Безкластерне дерево лишається видимим у будь-якому контексті — воно ще не
      # належить жодній організації (`OR trees.cluster_id IS NULL`), і це не acting-org
      # правило, а наявна семантика щойно заведеного вузла.
      expect(in_own).to include(clusterless_tree)
      expect(in_other).to include(clusterless_tree)
    end

    it "excludes trees from other organizations for forester" do
      forester = create(:user, :forester, organization: organization)
      scope = described_class::Scope.new(forester, Tree).resolve
      expect(scope).to include(own_tree)
      expect(scope).not_to include(other_tree)
    end

    it "excludes trees from other organizations for admin" do
      admin = create(:user, :admin, organization: organization)
      scope = described_class::Scope.new(admin, Tree).resolve
      expect(scope).to include(own_tree)
      expect(scope).not_to include(other_tree)
      expect(scope).to include(clusterless_tree)
    end
  end

  describe "#index?" do
    let(:tree) { create(:tree, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:admin) { create(:user, :admin, organization: organization) }

    it "returns true for all users" do
      expect(described_class.new(investor, tree).index?).to be true
      expect(described_class.new(forester, tree).index?).to be true
      expect(described_class.new(admin, tree).index?).to be true
      expect(described_class.new(super_admin, tree).index?).to be true
    end
  end

  describe "#show?" do
    let(:tree) { create(:tree, cluster: cluster) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:admin) { create(:user, :admin, organization: organization) }

    it "returns true for all users" do
      expect(described_class.new(investor, tree).show?).to be true
      expect(described_class.new(forester, tree).show?).to be true
      expect(described_class.new(admin, tree).show?).to be true
      expect(described_class.new(super_admin, tree).show?).to be true
    end
  end
end

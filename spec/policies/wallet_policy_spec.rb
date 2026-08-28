# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:subscriber) { create(:user, :subscriber, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
  end

  describe "#show?" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    it "allows admin" do
      expect(described_class.new(admin, wallet).show?).to be true
    end

    it "allows user from same org" do
      expect(described_class.new(subscriber, wallet).show?).to be true
    end

    context "when wallet belongs to another org" do
      let(:other_cluster) { create(:cluster, organization: other_org) }
      let(:other_tree) { create(:tree, cluster: other_cluster) }
      let(:other_wallet) { other_tree.wallet }

      it "denies user from different org" do
        expect(described_class.new(subscriber, other_wallet).show?).to be false
      end

      # [SEC.25 Ф2] Доти рядок звався «allows super_admin» і був правдою: платформена
      # роль відмикала скарбницю будь-якої організації. Тепер вирішує КОНТЕКСТ, і
      # перевіряти це треба двома суб'єктами — з одним не відрізнити «acting-організація»
      # від «власна» чи «перша-ліпша».
      it "дозволяє super_admin лише в контексті організації-власника" do
        expect(described_class.new(UserContext.new(super_admin, other_org), other_wallet).show?).to be true
        expect(described_class.new(UserContext.new(super_admin, organization), other_wallet).show?).to be false
      end
    end
  end

  describe "Scope" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_tree) { create(:tree, cluster: cluster) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    it "scopes to org wallets for regular user" do
      scope = described_class::Scope.new(subscriber, Wallet).resolve
      expect(scope).to include(own_tree.wallet)
      expect(scope).not_to include(other_tree.wallet)
    end

    it "звужує super_admin до acting-організації, і перемикання її змінює" do
      in_own = described_class::Scope.new(UserContext.new(super_admin, organization), Wallet).resolve
      in_other = described_class::Scope.new(UserContext.new(super_admin, other_org), Wallet).resolve

      expect(in_own).to include(own_tree.wallet)
      expect(in_own).not_to include(other_tree.wallet)
      expect(in_other).to include(other_tree.wallet)
      expect(in_other).not_to include(own_tree.wallet)
    end

    it "scopes admin to own org (org-scoped, not platform)" do
      scope = described_class::Scope.new(admin, Wallet).resolve
      expect(scope).to include(own_tree.wallet)
      expect(scope).not_to include(other_tree.wallet)
    end

    # [ARCH.87] Дискримінуючий приклад: гаманець, чия ДЕНОРМАЛІЗОВАНА колонка порожня,
    # але ланцюг `tree → cluster → organization` резолвиться. Доти `Scope` приймав лише
    # колонку, тож такий гаманець зникав зі списку й із суми ліквідності — а `show?` його
    # відкривав. Список і пряма адреса відповідали на «чий це гаманець» по-різному.
    context "when the denormalised column is blank but the chain resolves" do
      let!(:chain_only) do
        tree = create(:tree, cluster: cluster)
        tree.wallet.update_columns(organization_id: nil)
        tree.wallet
      end

      it "is visible to its own organization" do
        scope = described_class::Scope.new(subscriber, Wallet).resolve
        expect(scope).to include(chain_only)
      end

      it "stays invisible to a foreign organization" do
        foreign = described_class::Scope.new(UserContext.new(super_admin, other_org), Wallet).resolve
        expect(foreign).not_to include(chain_only)
      end

      it "answers the same as #show? — list and direct address must not diverge" do
        expect(described_class.new(subscriber, chain_only).show?).to be true
        expect(described_class::Scope.new(subscriber, Wallet).resolve).to include(chain_only)
      end
    end
  end

  describe "#index?" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }
    let(:forester) { create(:user, :forester, organization: organization) }

    it "returns true for all users" do
      expect(described_class.new(subscriber, wallet).index?).to be true
      expect(described_class.new(forester, wallet).index?).to be true
      expect(described_class.new(admin, wallet).index?).to be true
      expect(described_class.new(super_admin, wallet).index?).to be true
    end
  end

  describe "#show? when tree.cluster.organization_id is nil" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    it "denies access when wallet has no org chain and user is not admin" do
      allow(wallet).to receive_messages(organization_id: nil, tree: instance_double(Tree, cluster: nil))

      other_user = create(:user, :subscriber, organization: other_org)
      expect(described_class.new(other_user, wallet).show?).to be false
    end

    it "denies when tree has no cluster" do
      tree_double = instance_double(Tree, cluster: nil)
      allow(wallet).to receive_messages(organization_id: nil, tree: tree_double)

      expect(described_class.new(subscriber, wallet).show?).to be false
    end

    it "denies when wallet.tree is nil" do
      allow(wallet).to receive_messages(organization_id: nil, tree: nil)

      other_user = create(:user, :subscriber, organization: other_org)
      expect(described_class.new(other_user, wallet).show?).to be false
    end
  end

  describe "#balance?" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    it "delegates to show?" do
      expect(described_class.new(admin, wallet).balance?).to be true
    end
  end

  describe "#metadata?" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    it "delegates to show?" do
      expect(described_class.new(admin, wallet).metadata?).to be true
    end
  end
end

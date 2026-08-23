# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:organization) { create(:organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:record) { double("Record") }

  # [SEC.16] Deny-default: база ЗАБОРОНЯЄ читання, поки політика не дозволить явно.
  # Доти тут стояло `index?`/`show? == true` по чотирьох ролях — тобто спека
  # цементувала fail-open як задуману поведінку бази, і жодна мутація її не вбивала.
  describe "#index?" do
    it "denies by default — читання дозволяє лише політика, що визначила його явно" do
      expect(described_class.new(investor, record).index?).to be false
    end
  end

  describe "#create?" do
    it "denies investors" do
      expect(described_class.new(investor, record).create?).to be false
    end

    it "denies foresters" do
      expect(described_class.new(forester, record).create?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, record).create?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).create?).to be true
    end
  end

  describe "#show?" do
    # Роль тут свідомо НЕ вісь: дефолт відмовляє КОЖНОМУ, включно з super_admin —
    # інакше «база нічого не вирішує» знову означало б «база вирішує найширше».
    it "denies every role by default" do
      [ investor, forester, admin, super_admin ].each do |actor|
        expect(described_class.new(actor, record).show?).to be(false), "#{actor.role} пройшов дефолт"
      end
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

  describe "#initialize" do
    it "stores user and record" do
      policy = described_class.new(admin, record)
      expect(policy.user).to eq(admin)
      expect(policy.record).to eq(record)
    end
  end

  describe "private #admin_or_above?" do
    it "returns true for admin" do
      policy = described_class.new(admin, record)
      expect(policy.send(:admin_or_above?)).to be true
    end

    it "returns true for super_admin" do
      policy = described_class.new(super_admin, record)
      expect(policy.send(:admin_or_above?)).to be true
    end

    it "returns false for forester" do
      policy = described_class.new(forester, record)
      expect(policy.send(:admin_or_above?)).to be false
    end

    it "returns false for investor" do
      policy = described_class.new(investor, record)
      expect(policy.send(:admin_or_above?)).to be false
    end
  end

  describe "private #super_admin?" do
    it "returns true for super_admin" do
      policy = described_class.new(super_admin, record)
      expect(policy.send(:super_admin?)).to be true
    end

    it "returns false for admin" do
      policy = described_class.new(admin, record)
      expect(policy.send(:super_admin?)).to be false
    end

    it "returns false for forester" do
      policy = described_class.new(forester, record)
      expect(policy.send(:super_admin?)).to be false
    end

    it "returns false for investor" do
      policy = described_class.new(investor, record)
      expect(policy.send(:super_admin?)).to be false
    end
  end

  describe "private #forester_or_above?" do
    it "returns true for forester" do
      policy = described_class.new(forester, record)
      expect(policy.send(:forester_or_above?)).to be true
    end

    it "returns true for admin" do
      policy = described_class.new(admin, record)
      expect(policy.send(:forester_or_above?)).to be true
    end

    it "returns true for super_admin" do
      policy = described_class.new(super_admin, record)
      expect(policy.send(:forester_or_above?)).to be true
    end

    it "returns false for investor" do
      policy = described_class.new(investor, record)
      expect(policy.send(:forester_or_above?)).to be false
    end
  end

  describe "private #same_organization?" do
    it "returns true when user belongs to the same organization" do
      policy = described_class.new(admin, record)
      expect(policy.send(:same_organization?, organization.id)).to be true
    end

    it "returns false when user belongs to a different organization" do
      other_org = create(:organization)
      policy = described_class.new(admin, record)
      expect(policy.send(:same_organization?, other_org.id)).to be false
    end

    it "returns false when user has no organization" do
      # super_admin has no org
      policy = described_class.new(super_admin, record)
      expect(policy.send(:same_organization?, organization.id)).to be false
    end

    it "returns false when resource org_id is nil" do
      policy = described_class.new(admin, record)
      expect(policy.send(:same_organization?, nil)).to be false
    end
  end

  describe "Scope" do
    describe "#initialize" do
      it "stores user and scope" do
        scope_instance = described_class::Scope.new(admin, Tree)
        expect(scope_instance.send(:user)).to eq(admin)
        expect(scope_instance.send(:scope)).to eq(Tree)
      end
    end

    describe "#resolve" do
      before do
        silence_broadcasts!(:tree_map, :wallet_balance)
      end

      # 🔴 Доти обидва приклади звалися «returns scope.all» і асертили лише
      # `be_a(ActiveRecord::Relation)` — а `scope.none` теж Relation, тож вони
      # проходили б за БУДЬ-ЯКОЇ поведінки й не могли виразити дефект, який нібито
      # стерегли. Тепер пінимо ВМІСТ: забутий `Scope` віддає порожньо, не всю таблицю.
      it "resolves to NOTHING by default — навіть коли в таблиці є рядки" do
        create(:tree)

        expect(described_class::Scope.new(investor, Tree).resolve).to be_empty
      end

      it "denies super_admin the same way — роль не обходить дефолт" do
        create(:tree)

        expect(described_class::Scope.new(super_admin, Tree).resolve).to be_empty
      end
    end

    describe "private #admin_or_above?" do
      it "returns true for admin" do
        scope_instance = described_class::Scope.new(admin, Tree)
        expect(scope_instance.send(:admin_or_above?)).to be true
      end

      it "returns false for forester" do
        scope_instance = described_class::Scope.new(forester, Tree)
        expect(scope_instance.send(:admin_or_above?)).to be false
      end
    end

    describe "private #super_admin?" do
      it "returns true for super_admin" do
        scope_instance = described_class::Scope.new(super_admin, Tree)
        expect(scope_instance.send(:super_admin?)).to be true
      end

      it "returns false for admin" do
        scope_instance = described_class::Scope.new(admin, Tree)
        expect(scope_instance.send(:super_admin?)).to be false
      end
    end
  end
end

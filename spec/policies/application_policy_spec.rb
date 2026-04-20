# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:organization) { create(:organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:record) { double("Record") }

  describe "#index?" do
    it "allows all authenticated users" do
      expect(described_class.new(investor, record).index?).to be true
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
        allow_any_instance_of(Tree).to receive(:broadcast_map_update)
        allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
      end

      it "returns scope.all for any user" do
        scope = described_class::Scope.new(investor, Tree).resolve
        expect(scope).to be_a(ActiveRecord::Relation)
      end

      it "returns scope.all for super_admin" do
        scope = described_class::Scope.new(super_admin, Tree).resolve
        expect(scope).to be_a(ActiveRecord::Relation)
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

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

  describe "Scope#resolve" do
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
end

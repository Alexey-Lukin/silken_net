# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilyPolicy do
  let(:organization) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:record) { double("Record") }

  describe "#index?" do
    it "allows investors" do
      expect(described_class.new(investor, record).index?).to be true
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).index?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).index?).to be true
    end
  end

  describe "#show?" do
    it "allows investors" do
      expect(described_class.new(investor, record).show?).to be true
    end

    it "allows foresters" do
      expect(described_class.new(forester, record).show?).to be true
    end

    it "allows admins" do
      expect(described_class.new(admin, record).show?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, record).show?).to be true
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

  describe "Scope" do
    let!(:family_a) { create(:tree_family) }
    let!(:family_b) { create(:tree_family) }

    it "returns all tree families for any user" do
      scope = described_class::Scope.new(investor, TreeFamily).resolve
      expect(scope).to include(family_a, family_b)
    end

    it "returns all tree families for super_admins" do
      scope = described_class::Scope.new(super_admin, TreeFamily).resolve
      expect(scope).to include(family_a, family_b)
    end
  end
end

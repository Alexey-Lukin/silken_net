# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationPolicy do
  let(:organization) { create(:organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "#index?" do
    it "denies investors" do
      expect(described_class.new(investor, Organization).index?).to be false
    end

    it "denies admins" do
      expect(described_class.new(admin, Organization).index?).to be false
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, Organization).index?).to be true
    end
  end

  describe "#show?" do
    it "denies investors" do
      expect(described_class.new(investor, organization).show?).to be false
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, organization).show?).to be true
    end
  end

  describe "Scope#resolve" do
    let!(:org1) { organization }
    let(:other_org) { create(:organization) }
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

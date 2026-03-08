# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "#index?" do
    it "denies investors" do
      expect(described_class.new(investor, User).index?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, User).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, User).index?).to be true
    end
  end

  describe "#me?" do
    it "allows any authenticated user" do
      expect(described_class.new(investor, investor).me?).to be true
    end
  end

  describe "Scope" do
    let!(:org_user) { create(:user, :forester, organization: organization) }
    let!(:other_user) { create(:user, :forester, organization: other_org) }

    it "scopes to organization for admin" do
      scope = described_class::Scope.new(admin, User).resolve
      expect(scope).to include(org_user)
      expect(scope).not_to include(other_user)
    end

    it "returns all for super_admin" do
      scope = described_class::Scope.new(super_admin, User).resolve
      expect(scope).to include(org_user, other_user)
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
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

    it "denies foresters" do
      forester = create(:user, :forester, organization: organization)
      expect(described_class.new(forester, User).index?).to be false
    end

    it "allows admins" do
      expect(described_class.new(admin, User).index?).to be true
    end

    it "allows super_admins" do
      expect(described_class.new(super_admin, User).index?).to be true
    end
  end

  describe "#show?" do
    it "allows viewing users in the same organization" do
      other_user = create(:user, :forester, organization: organization)
      expect(described_class.new(admin, other_user).show?).to be true
    end

    it "denies viewing users in a different organization" do
      other_org_user = create(:user, :forester, organization: other_org)
      expect(described_class.new(admin, other_org_user).show?).to be false
    end

    it "allows super_admin to view any user (show? mirrors Scope.all)" do
      other_org_user = create(:user, :forester, organization: other_org)
      expect(described_class.new(super_admin, other_org_user).show?).to be true
    end

    it "allows investor to view users in the same org" do
      same_org_user = create(:user, :forester, organization: organization)
      expect(described_class.new(investor, same_org_user).show?).to be true
    end
  end

  describe "#me?" do
    it "allows any authenticated user" do
      expect(described_class.new(investor, investor).me?).to be true
    end

    it "allows admin" do
      expect(described_class.new(admin, admin).me?).to be true
    end

    it "allows super_admin" do
      expect(described_class.new(super_admin, super_admin).me?).to be true
    end
  end

  describe "#create?" do
    it "denies investors (inherited from ApplicationPolicy)" do
      expect(described_class.new(investor, User).create?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).create?).to be true
    end
  end

  describe "#update?" do
    it "denies investors (inherited from ApplicationPolicy)" do
      expect(described_class.new(investor, User).update?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).update?).to be true
    end
  end

  describe "#destroy?" do
    it "denies investors (inherited from ApplicationPolicy)" do
      expect(described_class.new(investor, User).destroy?).to be false
    end

    it "allows admins (inherited from ApplicationPolicy)" do
      expect(described_class.new(admin, User).destroy?).to be true
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

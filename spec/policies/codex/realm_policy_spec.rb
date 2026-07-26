# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Codex::RealmPolicy — read-only for any authenticated user; writes inherited
# from Codex::ApplicationPolicy (denied for everyone). Scope#resolve hides
# soft-disabled realms (`is_active = false`) from the public listing.
RSpec.describe Codex::RealmPolicy, type: :policy do
  let(:investor)    { create(:user, :investor) }
  let(:forester)    { create(:user, :forester) }
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:realm)       { create(:codex_realm) }

  describe "#index? / #show?" do
    it "permits any authenticated user" do
      [ investor, forester, admin, super_admin ].each do |u|
        expect(described_class.new(u, realm).index?).to be(true)
        expect(described_class.new(u, realm).show?).to  be(true)
      end
    end

    it "denies anonymous user" do
      expect(described_class.new(nil, realm).index?).to be(false)
      expect(described_class.new(nil, realm).show?).to  be(false)
    end
  end

  describe "#create? / #update? / #destroy? (inherited deny defaults)" do
    it "denies writes for every role including super_admin" do
      [ investor, forester, admin, super_admin ].each do |u|
        policy = described_class.new(u, realm)
        expect(policy.create?).to  be(false)
        expect(policy.update?).to  be(false)
        expect(policy.destroy?).to be(false)
      end
    end
  end

  describe "Scope#resolve" do
    let!(:active_realm)   { create(:codex_realm, is_active: true) }
    let!(:inactive_realm) { create(:codex_realm, is_active: false) }

    it "returns only active realms (hides soft-disabled)" do
      result = described_class::Scope.new(investor, Codex::Realm).resolve
      expect(result).to include(active_realm)
      expect(result).not_to include(inactive_realm)
    end

    it "applies the same filter for super_admin (no admin escape hatch in Phase 1)" do
      result = described_class::Scope.new(super_admin, Codex::Realm).resolve
      expect(result).not_to include(inactive_realm)
    end
  end
end

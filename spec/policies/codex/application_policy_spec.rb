# frozen_string_literal: true

require "rails_helper"

# Codex::ApplicationPolicy is the safe-default base class for every Codex
# policy. Subclasses override individual predicates, but if a future policy
# forgets to do so, these specs guarantee the inherited behaviour is:
#   - read = any authenticated user, anonymous denied
#   - write = denied for everyone (must be opted-in)
#   - Scope#resolve = returns scope.all (no implicit visibility filter)
RSpec.describe Codex::ApplicationPolicy, type: :policy do
  let(:investor)    { create(:user, :investor) }
  let(:forester)    { create(:user, :forester) }
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:record)      { Object.new } # generic record — base class does not introspect it

  describe "#index? / #show? (read defaults)" do
    it "permits any authenticated user" do
      [ investor, forester, admin, super_admin ].each do |u|
        policy = described_class.new(u, record)
        expect(policy.index?).to be(true), "expected #{u.role} to read index"
        expect(policy.show?).to  be(true), "expected #{u.role} to read show"
      end
    end

    it "denies anonymous user" do
      policy = described_class.new(nil, record)
      expect(policy.index?).to be(false)
      expect(policy.show?).to  be(false)
    end
  end

  describe "#create? / #update? / #destroy? (write defaults)" do
    it "denies for every role including super_admin (must be opted-in by subclass)" do
      [ investor, forester, admin, super_admin ].each do |u|
        policy = described_class.new(u, record)
        expect(policy.create?).to  be(false), "expected #{u.role} to be denied create"
        expect(policy.update?).to  be(false), "expected #{u.role} to be denied update"
        expect(policy.destroy?).to be(false), "expected #{u.role} to be denied destroy"
      end
    end

    it "denies for anonymous user" do
      policy = described_class.new(nil, record)
      expect(policy.create?).to  be(false)
      expect(policy.update?).to  be(false)
      expect(policy.destroy?).to be(false)
    end
  end

  describe "Scope#resolve" do
    let!(:realm_a) { create(:codex_realm) }
    let!(:realm_b) { create(:codex_realm, is_active: false) }

    it "returns scope.all (no implicit filtering)" do
      result = described_class::Scope.new(investor, Codex::Realm).resolve
      expect(result).to include(realm_a, realm_b)
    end

    it "is a real subclass of ApplicationPolicy::Scope (inherits initializer)" do
      expect(described_class::Scope.ancestors).to include(::ApplicationPolicy::Scope)
    end
  end
end

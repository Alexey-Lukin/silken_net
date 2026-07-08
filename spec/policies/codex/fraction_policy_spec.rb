# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::FractionPolicy, type: :policy do
  subject(:policy) { described_class.new(user, fraction) }

  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:fraction) { create(:codex_fraction, user: user) }
  let(:other_fraction) { create(:codex_fraction, user: other) }

  describe "permissions" do
    it "permits index/show for any authenticated user" do
      expect(described_class.new(user, fraction).index?).to be(true)
      expect(described_class.new(user, fraction).show?).to be(true)
      expect(described_class.new(nil, fraction).index?).to be(false)
      expect(described_class.new(nil, fraction).show?).to be(false)
    end

    it "permits create for any authenticated user" do
      expect(described_class.new(user, Codex::Fraction.new).create?).to be(true)
      expect(described_class.new(nil, Codex::Fraction.new).create?).to be(false)
    end

    it "permits update/destroy only on own record" do
      expect(described_class.new(user, fraction).update?).to be(true)
      expect(described_class.new(user, fraction).destroy?).to be(true)
      expect(described_class.new(user, other_fraction).update?).to be(false)
      expect(described_class.new(user, other_fraction).destroy?).to be(false)
    end

    it "denies update/destroy for anonymous users" do
      expect(described_class.new(nil, fraction).update?).to be(false)
      expect(described_class.new(nil, fraction).destroy?).to be(false)
    end
  end

  describe "Scope#resolve" do
    it "returns the unscoped collection" do
      fraction
      expect(described_class::Scope.new(user, Codex::Fraction.all).resolve).to include(fraction)
    end
  end
end

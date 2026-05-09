# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryRulePolicy, type: :policy do
  let(:user)        { create(:user) }
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:rule)        { create(:codex_discovery_rule) }

  %i[index? show? create? update? destroy?].each do |action|
    it "#{action} → admin denies non-admin" do
      expect(described_class.new(user, rule).public_send(action)).to be(false)
    end

    it "#{action} → admin allows admin" do
      expect(described_class.new(admin, rule).public_send(action)).to be(true)
    end

    it "#{action} → admin allows super_admin" do
      expect(described_class.new(super_admin, rule).public_send(action)).to be(true)
    end
  end

  describe "Scope" do
    it "returns all for admin, none for non-admin" do
      rule
      expect(described_class::Scope.new(admin, Codex::DiscoveryRule.all).resolve).to contain_exactly(rule)
      expect(described_class::Scope.new(user, Codex::DiscoveryRule.all).resolve.count).to eq(0)
      expect(described_class::Scope.new(nil, Codex::DiscoveryRule.all).resolve.count).to eq(0)
    end
  end
end

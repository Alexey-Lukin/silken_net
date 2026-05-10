# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::NodePolicy do
  let(:org)         { create(:organization) }
  let(:investor)    { create(:user, :investor,    organization: org) }
  let(:forester)    { create(:user, :forester,    organization: org) }
  let(:admin)       { create(:user, :admin,       organization: org) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:node)        { create(:codex_node) }

  describe "#index? / #show?" do
    it "allow any authenticated user" do
      [ investor, forester, admin, super_admin ].each do |u|
        expect(described_class.new(u, node).index?).to be(true)
        expect(described_class.new(u, node).show?).to be(true)
      end
    end

    it "deny anonymous user" do
      expect(described_class.new(nil, node)).not_to be_index
      expect(described_class.new(nil, node)).not_to be_show
    end
  end

  describe "#create? / #update? / #destroy?" do
    it "permit only super_admin" do
      expect(described_class.new(super_admin, node).create?).to be(true)
      expect(described_class.new(super_admin, node).update?).to be(true)
      expect(described_class.new(super_admin, node).destroy?).to be(true)
    end

    it "deny non-super_admin roles" do
      [ investor, forester, admin ].each do |u|
        expect(described_class.new(u, node)).not_to be_create
        expect(described_class.new(u, node)).not_to be_update
        expect(described_class.new(u, node)).not_to be_destroy
      end
    end
  end

  describe "Scope#resolve" do
    let!(:published) { create(:codex_node, published_at: Time.current) }
    let!(:draft)     { create(:codex_node, published_at: nil) }

    it "returns only published nodes for non-super_admin users" do
      result = described_class::Scope.new(investor, Codex::Node).resolve
      expect(result).to include(published)
      expect(result).not_to include(draft)
    end

    it "returns drafts as well for super_admin" do
      result = described_class::Scope.new(super_admin, Codex::Node).resolve
      expect(result).to include(published, draft)
    end
  end
end

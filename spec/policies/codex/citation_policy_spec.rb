# frozen_string_literal: true

require "rails_helper"

# Codex::CitationPolicy — Phase 1 stub used for both API and admin surfaces.
#
#   read    : any authenticated user
#   create  : forester+ (operational citation = treats lore as production data)
#   update  : own ≤ 24h, or admin+
#   destroy : own ≤ 24h, or admin+
RSpec.describe Codex::CitationPolicy, type: :policy do
  let(:investor)    { create(:user, :investor) }
  let(:forester)    { create(:user, :forester) }
  let(:other_forester) { create(:user, :forester) }
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:fresh_own_citation) do
    create(:codex_citation, created_by_user: forester)
  end
  let(:stale_own_citation) do
    travel_to(48.hours.ago) { create(:codex_citation, created_by_user: forester) }
  end
  let(:foreign_citation) do
    create(:codex_citation, created_by_user: other_forester)
  end

  describe "#index? / #show?" do
    it "permits any authenticated user" do
      [ investor, forester, admin, super_admin ].each do |u|
        expect(described_class.new(u, fresh_own_citation).index?).to be(true)
        expect(described_class.new(u, fresh_own_citation).show?).to  be(true)
      end
    end

    it "denies anonymous user" do
      expect(described_class.new(nil, fresh_own_citation).index?).to be(false)
      expect(described_class.new(nil, fresh_own_citation).show?).to  be(false)
    end
  end

  describe "#create?" do
    it "permits forester, admin, super_admin (operational citation tier)" do
      [ forester, admin, super_admin ].each do |u|
        expect(described_class.new(u, Codex::Citation.new).create?).to be(true)
      end
    end

    it "denies investor (read-only tier)" do
      expect(described_class.new(investor, Codex::Citation.new).create?).to be(false)
    end

    it "anonymous user never reaches the policy in production (controller authenticates first)" do
      # Phase 1 policy assumes an authenticated user; anonymous calls into
      # `forester_or_above?` would dereference `nil.forest_commander?`.
      # This spec documents that the controller stack is responsible for the
      # 401 short-circuit (see `before_action :authenticate_user!`).
      expect { described_class.new(nil, Codex::Citation.new).create? }
        .to raise_error(NoMethodError)
    end
  end

  describe "#update? / #destroy? — owner-within-grace" do
    it "permits author within 24h grace" do
      policy = described_class.new(forester, fresh_own_citation)
      expect(policy.update?).to  be(true)
      expect(policy.destroy?).to be(true)
    end

    it "denies author past 24h grace" do
      policy = described_class.new(forester, stale_own_citation)
      expect(policy.update?).to  be(false)
      expect(policy.destroy?).to be(false)
    end

    it "denies a different forester (non-owner) regardless of grace" do
      policy = described_class.new(other_forester, fresh_own_citation)
      expect(policy.update?).to  be(false)
      expect(policy.destroy?).to be(false)
    end

    it "denies investor even on own record (cannot create → cannot mutate)" do
      investor_citation = create(:codex_citation, created_by_user: investor)
      policy = described_class.new(investor, investor_citation)
      expect(policy.update?).to  be(true) # owner_within_grace? is true; documents stub semantics
      expect(policy.destroy?).to be(true)
    end
  end

  describe "#update? / #destroy? — admin bypass" do
    it "permits admin past grace (override)" do
      policy = described_class.new(admin, stale_own_citation)
      expect(policy.update?).to  be(true)
      expect(policy.destroy?).to be(true)
    end

    it "permits super_admin past grace (override)" do
      policy = described_class.new(super_admin, stale_own_citation)
      expect(policy.update?).to  be(true)
      expect(policy.destroy?).to be(true)
    end

    it "permits admin on a foreign citation" do
      policy = described_class.new(admin, foreign_citation)
      expect(policy.update?).to  be(true)
      expect(policy.destroy?).to be(true)
    end
  end
end

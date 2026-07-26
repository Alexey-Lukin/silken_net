# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Codex::CitationPolicy — RBAC-матриця поверхні цитат:
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

    it "raises NoMethodError for nil user (documents controller-level auth gate)" do
      # Policy assumes an authenticated user is always present;
      # `forester_or_above?` calls `user.forest_commander?` which fails on nil.
      # The controller's `before_action :authenticate_user!` prevents this path.
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

    it "permits investor on own record within grace (policy does not gate by role — create? does)" do
      # The policy's update?/destroy? uses owner_within_grace? || admin_or_above?.
      # An investor cannot create citations (create? returns false), but if one
      # were to exist in DB, update?/destroy? would permit within 24h.
      # This documents the deliberate design: create? is the gate, not update?/destroy?.
      investor_citation = create(:codex_citation, created_by_user: investor)
      policy = described_class.new(investor, investor_citation)
      expect(policy.update?).to  be(true)
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

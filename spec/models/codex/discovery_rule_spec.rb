# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryRule, type: :model do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  it "has a valid factory" do
    expect(build(:codex_discovery_rule, node: node, created_by_user: user)).to be_valid
  end

  describe "validations" do
    it "requires name" do
      r = build(:codex_discovery_rule, name: "")
      expect(r).not_to be_valid
      expect(r.errors[:name]).to be_present
    end

    it "requires threshold ≥ 1" do
      r = build(:codex_discovery_rule, threshold_value: 0)
      expect(r).not_to be_valid
    end

    it "rejects non-hash params" do
      r = build(:codex_discovery_rule)
      r.params = "not a hash"
      expect(r).not_to be_valid
      expect(r.errors[:params]).to include("must be a JSON object")
    end
  end

  describe "scopes" do
    it "active_only filters out inactive" do
      a = create(:codex_discovery_rule, active: true)
      _i = create(:codex_discovery_rule, active: false)
      expect(described_class.active_only).to contain_exactly(a)
    end

    it "for_condition filters by enum" do
      mc  = create(:codex_discovery_rule, condition_type: :match_count)
      _t = create(:codex_discovery_rule, condition_type: :tree_observation_minutes)
      expect(described_class.for_condition(:match_count)).to contain_exactly(mc)
    end
  end

  describe ".cached_active_by_condition" do
    before { Rails.cache.clear }

    it "returns active rules grouped by condition_type, lazily loaded" do
      r1 = create(:codex_discovery_rule, condition_type: :match_count)
      r2 = create(:codex_discovery_rule, condition_type: :match_count)
      r3 = create(:codex_discovery_rule, condition_type: :oracle_dispatched)
      _inactive = create(:codex_discovery_rule, condition_type: :match_count, active: false)

      result = described_class.cached_active_by_condition
      expect(result["match_count"].map(&:id)).to contain_exactly(r1.id, r2.id)
      expect(result["oracle_dispatched"].map(&:id)).to contain_exactly(r3.id)
    end

    it "busts cache after_commit on save" do
      first = described_class.cached_active_by_condition
      expect(first.values.flatten).to be_empty

      create(:codex_discovery_rule, condition_type: :match_count)
      second = described_class.cached_active_by_condition
      expect(second["match_count"]).not_to be_empty
    end
  end
end

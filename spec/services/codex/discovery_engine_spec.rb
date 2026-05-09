# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryEngine, type: :service do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  before { Rails.cache.clear }

  describe "no rules" do
    it "returns []" do
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to eq([])
    end
  end

  describe "match_count adapter" do
    let(:realm) { create(:codex_realm) }
    let(:left)  { create(:codex_node, realm: realm) }
    let(:right) { create(:codex_node, realm: realm) }
    let!(:rule) do
      create(:codex_discovery_rule, node: node, condition_type: :match_count, threshold_value: 2)
    end

    it "fires once user has ≥ threshold matches" do
      2.times { create(:codex_match, user: user, realm: realm, left: left, right: right) }
      result = described_class.evaluate(user: user, trigger_type: :match_milestone)
      expect(result).to contain_exactly(node)
    end

    it "does not fire below threshold" do
      create(:codex_match, user: user, realm: realm, left: left, right: right)
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to eq([])
    end

    it "scopes by realm_slug param when present" do
      other_realm = create(:codex_realm, slug: "mythos_test")
      rule.update!(params: { "realm_slug" => "mythos_test" })
      2.times { create(:codex_match, user: user, realm: realm, left: left, right: right) }
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to eq([])

      o_left  = create(:codex_node, realm: other_realm)
      o_right = create(:codex_node, realm: other_realm)
      2.times { create(:codex_match, user: user, realm: other_realm, left: o_left, right: o_right) }
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to contain_exactly(node)
    end
  end

  describe "skip already-unlocked" do
    let!(:rule) do
      create(:codex_discovery_rule, node: node, condition_type: :match_count, threshold_value: 1)
    end
    let(:realm) { create(:codex_realm) }

    it "does not double-unlock existing Discovery" do
      create(:codex_match, user: user, realm: realm,
                           left: create(:codex_node, realm: realm),
                           right: create(:codex_node, realm: realm))
      create(:codex_discovery, user: user, node: node)
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to eq([])
    end
  end

  describe "inert rule (below threshold) → no-op" do
    # Phase 6 — every condition_type now has an adapter, so the
    # historical "unknown condition" guard is exercised by stubbing
    # the ADAPTERS hash. The adapter still skips rules whose Node is
    # already unlocked (covered above) and whose count is below the
    # threshold (covered here for `acoustic_class_count`).
    it "skips rules whose threshold has not been crossed" do
      create(:codex_discovery_rule, node: node, condition_type: :acoustic_class_count, threshold_value: 1)
      expect(described_class.evaluate(user: user, trigger_type: :telemetry_observation)).to eq([])
    end

    it "logs and skips when the adapter for a rule is missing" do
      create(:codex_discovery_rule, node: node, condition_type: :match_count, threshold_value: 1)
      stub_const("#{described_class}::ADAPTERS", {})
      expect(Rails.logger).to receive(:debug).at_least(:once)
      expect(described_class.evaluate(user: user, trigger_type: :match_milestone)).to eq([])
    end
  end

  describe "Phase 6 adapters" do
    it "acoustic_class_count is inert when user has no organization" do
      user.update!(organization_id: nil)
      create(:codex_discovery_rule, node: node, condition_type: :acoustic_class_count, threshold_value: 1)
      expect(described_class.evaluate(user: user, trigger_type: :telemetry_observation)).to eq([])
    end

    it "cluster_visited is inert when params['cluster_name'] is missing" do
      create(:codex_discovery_rule,
             node: node, condition_type: :cluster_visited, threshold_value: 1, params: {})
      expect(described_class.evaluate(user: user, trigger_type: :telemetry_observation)).to eq([])
    end

    it "firmware_version_seen is inert when no firmware row matches" do
      create(:codex_discovery_rule,
             node: node, condition_type: :firmware_version_seen,
             threshold_value: 1, params: { "version" => "v9.999.999" })
      expect(described_class.evaluate(user: user, trigger_type: :telemetry_observation)).to eq([])
    end
  end

  describe "guard rails" do
    it "returns [] for an unsaved user" do
      expect(described_class.evaluate(user: User.new, trigger_type: :match_milestone)).to eq([])
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
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
    # every condition_type now has an adapter, so the
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

  describe "Phase 6 adapter happy-paths" do
    let(:org)     { create(:organization) }
    let(:cluster) { create(:cluster, name: "Sector Alpha", organization: org) }
    let(:tree)    { create(:tree, cluster: cluster) }

    before do
      user.update!(organization_id: org.id)
      Rails.cache.clear
    end

    describe "tree_observation_minutes" do
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :tree_observation_minutes,
               threshold_value: 10, # needs 10 "minutes" ≈ 2 logs × 5 min effective period
               params: { "window_days" => 30, "effective_period_minutes" => 5 })
      end

      it "fires when enough telemetry logs exist within the window" do
        2.times { create(:telemetry_log, tree: tree) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to contain_exactly(node)
      end

      it "does not fire when logs are below threshold" do
        create(:telemetry_log, tree: tree) # 1 * 5 = 5 < 10
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end
    end

    describe "attunement_streak_days" do
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :attunement_streak_days,
               threshold_value: 3) # 3 consecutive days needed
      end

      it "fires when user has attunements on consecutive trailing days" do
        3.times do |i|
          travel_to(i.days.ago) { create(:codex_attunement, user: user) }
        end
        result = described_class.evaluate(user: user, trigger_type: :attunement_streak)
        expect(result).to contain_exactly(node)
      end

      it "does not fire when streak is broken (gap in the middle)" do
        # Today + 2 days ago (skipping yesterday)
        create(:codex_attunement, user: user)
        travel_to(2.days.ago) { create(:codex_attunement, user: user) }
        result = described_class.evaluate(user: user, trigger_type: :attunement_streak)
        expect(result).to eq([])
      end
    end

    describe "oracle_dispatched" do
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :oracle_dispatched,
               threshold_value: 2)
      end

      it "fires when enough TelemetryLogs have oracle_status dispatched/fulfilled" do
        create(:telemetry_log, tree: tree, oracle_status: :dispatched)
        create(:telemetry_log, tree: tree, oracle_status: :fulfilled)
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to contain_exactly(node)
      end

      it "does not fire when count is below threshold" do
        create(:telemetry_log, tree: tree, oracle_status: :dispatched)
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end

      it "does not count pending/failed statuses" do
        2.times { create(:telemetry_log, tree: tree, oracle_status: :pending) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end
    end

    describe "acoustic_class_count" do
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :acoustic_class_count,
               threshold_value: 2,
               params: { "min_events" => 15 })
      end

      it "fires when enough high-acoustic logs exist" do
        2.times { create(:telemetry_log, tree: tree, acoustic_events: 20) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to contain_exactly(node)
      end

      it "does not count logs below min_events" do
        3.times { create(:telemetry_log, tree: tree, acoustic_events: 10) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end
    end

    describe "cluster_visited" do
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :cluster_visited,
               threshold_value: 2,
               params: { "cluster_name" => "Sector Alpha" })
      end

      it "fires when enough logs from trees inside the cluster exist" do
        2.times { create(:telemetry_log, tree: tree) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to contain_exactly(node)
      end

      it "does not fire for trees in a different cluster" do
        other_cluster = create(:cluster, name: "Sector Beta", organization: org)
        other_tree = create(:tree, cluster: other_cluster)
        3.times { create(:telemetry_log, tree: other_tree) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end

      it "does not fire when cluster_name does not match any Cluster record" do
        rule.update!(params: { "cluster_name" => "Nonexistent" })
        2.times { create(:telemetry_log, tree: tree) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end
    end

    describe "firmware_version_seen" do
      let(:firmware) { create(:bio_contract_firmware, version: "2.1.0") }
      let!(:rule) do
        create(:codex_discovery_rule,
               node: node,
               condition_type: :firmware_version_seen,
               threshold_value: 2,
               params: { "version" => "2.1.0" })
      end

      it "fires when enough logs reference the target firmware version" do
        2.times { create(:telemetry_log, tree: tree, firmware_version_id: firmware.id) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to contain_exactly(node)
      end

      it "does not fire when firmware_version_id points to a different version" do
        other_fw = create(:bio_contract_firmware, version: "1.0.0")
        3.times { create(:telemetry_log, tree: tree, firmware_version_id: other_fw.id) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end

      it "does not fire when params['version'] is blank" do
        rule.update!(params: { "version" => "" })
        2.times { create(:telemetry_log, tree: tree, firmware_version_id: firmware.id) }
        result = described_class.evaluate(user: user, trigger_type: :telemetry_observation)
        expect(result).to eq([])
      end
    end
  end

  describe "guard rails" do
    it "returns [] for an unsaved user" do
      expect(described_class.evaluate(user: User.new, trigger_type: :match_milestone)).to eq([])
    end

    it "returns [] for a nil user (safe-navigation guard)" do
      expect(described_class.evaluate(user: nil, trigger_type: :match_milestone)).to eq([])
    end
  end

  # Org-scoped adapters must return false when the user has no organization —
  # otherwise a personal account could unlock org-tier discoveries by accident.
  describe "organization_id-blank guard rails" do
    let(:user_no_org) { create(:user, organization: nil) }

    {
      tree_observation_minutes: { "window_days" => 30, "effective_period_minutes" => 5 },
      oracle_dispatched:        {},
      acoustic_class_count:     { "min_events" => 20 },
      cluster_visited:          { "cluster_name" => "Whatever" },
      firmware_version_seen:    { "version" => "1.2.3" }
    }.each do |condition_type, params|
      it "#{condition_type} returns false when user has no organization" do
        create(:codex_discovery_rule,
          node: node, condition_type: condition_type, threshold_value: 1, params: params)
        expect(
          described_class.evaluate(user: user_no_org, trigger_type: :match_milestone)
        ).to eq([])
      end
    end
  end

  describe "match_count with unknown realm_slug" do
    let(:realm) { create(:codex_realm) }
    let(:left)  { create(:codex_node, realm: realm) }
    let(:right) { create(:codex_node, realm: realm) }

    it "ignores the realm filter when the slug doesn't match any realm" do
      rule = create(:codex_discovery_rule,
        node: node, condition_type: :match_count, threshold_value: 1,
        params: { "realm_slug" => "no_such_realm" })
      2.times { create(:codex_match, user: user, realm: realm, left: left, right: right) }

      # Realm lookup returns nil → scope filter skipped → global match count
      # still satisfies threshold and unlocks the node.
      expect(
        described_class.evaluate(user: user, trigger_type: :match_milestone)
      ).to contain_exactly(node)
      expect(rule.reload.params["realm_slug"]).to eq("no_such_realm")
    end
  end
end

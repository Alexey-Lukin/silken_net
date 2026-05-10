# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::PairSelectorService, type: :service do
  let(:user)  { create(:user) }
  let(:realm) { create(:codex_realm) }

  describe "happy paths" do
    before do
      5.times { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
    end

    it "returns two distinct same-realm nodes plus a stable HMAC seed" do
      result = described_class.call(user: user, realm: realm)
      expect(result.success?).to be(true)
      expect(result.left).to be_present
      expect(result.right).to be_present
      expect(result.left.id).not_to eq(result.right.id)
      expect(result.left.codex_realm_id).to eq(realm.id)
      expect(result.right.codex_realm_id).to eq(realm.id)
      expect(result.pair_seed).to match(/\A[0-9a-f]{64}\z/)
    end

    it "stores the seed in Redis under codex:pair_seed:<seed> with TTL" do
      result = described_class.call(user: user, realm: realm)
      r = Kredis.redis(config: :shared)
      raw = r.get("codex:pair_seed:#{result.pair_seed}")
      expect(raw).to be_present
      ttl = r.ttl("codex:pair_seed:#{result.pair_seed}")
      expect(ttl).to be_between(1, described_class::SEED_TTL.to_i)
    end

    it "defaults to the first ordered realm when nil" do
      result = described_class.call(user: user, realm: nil)
      expect(result.success?).to be(true)
      expect(result.realm).to eq(::Codex::Realm.ordered.first)
    end
  end

  describe "failure paths" do
    it "fails when realm has fewer than 2 pickable nodes" do
      create(:codex_node, realm: realm, lifecycle_status: :thriving)
      create(:codex_node, realm: realm, lifecycle_status: :extinct)
      result = described_class.call(user: user, realm: realm)
      expect(result.success?).to be(false)
      expect(result.error).to match(/not enough nodes/)
    end

    it "fails for an unsaved user" do
      result = described_class.call(user: User.new, realm: realm)
      expect(result.success?).to be(false)
    end

    it "fails when no realm exists" do
      ::Codex::Realm.delete_all
      result = described_class.call(user: user, realm: nil)
      expect(result.success?).to be(false)
      expect(result.error).to match(/no realm/)
    end
  end

  describe "Elo bucketing" do
    it "prefers an opponent within ±200 Elo of the anchor when the bucket has ≥ 2 nodes" do
      # Cluster of 5 nodes at 1500; their bucket [1300..1700] is fully
      # populated, so any pair sampled from there must satisfy the
      # ±200 invariant. Outliers exist but are never reachable as the
      # *opponent* of a cluster node — only as a sole anchor with no
      # bucket peers (in which case the service falls back, also valid).
      5.times { create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 1500) }
      create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 2400)
      create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 800)

      30.times.map { described_class.call(user: user, realm: realm) }.each do |r|
        next unless r.success?
        anchor_in_cluster = (1300..1700).cover?(r.left.attunement_elo)
        next unless anchor_in_cluster

        diff = (r.left.attunement_elo - r.right.attunement_elo).abs
        expect(diff).to be <= described_class::ELO_BUCKET
      end
    end
  end

  describe "Redis unavailability" do
    before do
      5.times { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
    end

    it "returns a successful result even when Redis is unavailable (graceful degradation)" do
      allow(Kredis).to receive(:redis).and_raise(StandardError, "Redis connection refused")
      result = described_class.call(user: user, realm: realm)
      # Pair is still selected — seed storage failure is swallowed silently
      expect(result.success?).to be(true)
      expect(result.pair_seed).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end

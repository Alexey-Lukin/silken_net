# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::VoteRecorderService, type: :service do
  let(:user)  { create(:user) }
  let(:realm) { create(:codex_realm) }
  let!(:left)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let!(:right) { create(:codex_node, realm: realm, lifecycle_status: :thriving) }

  before { Sidekiq::Worker.clear_all }

  def issue_pair_seed
    seed = ::Codex::PairSelectorService.send(:new, user: user, realm: realm).send(:sign_pair, realm.id, left.id, right.id)
    r = Kredis.redis(config: :shared)
    r.setex(
      "codex:pair_seed:#{seed}",
      ::Codex::PairSelectorService::SEED_TTL.to_i,
      "#{user.id}|#{realm.id}|#{left.id}|#{right.id}|#{Time.current.to_i}"
    )
    seed
  end

  describe "happy paths" do
    it "creates a Match for a winner pick and enqueues EloRecomputeWorker" do
      seed = issue_pair_seed
      expect {
        result = described_class.call(user: user, pair_seed: seed, winner_slug: left.slug)
        expect(result.success?).to be(true)
        expect(result.match.winner_node_id).to eq(left.id)
        expect(result.match.elo_delta_left).to be > 0
        expect(result.match.elo_delta_right).to eq(-result.match.elo_delta_left)
      }.to change(Codex::EloRecomputeWorker.jobs, :size).by(1)
    end

    it "creates a skip match (no winner, zero deltas)" do
      seed = issue_pair_seed
      result = described_class.call(user: user, pair_seed: seed, skip: true)
      expect(result.success?).to be(true)
      expect(result.match.winner_node_id).to be_nil
      expect(result.match.elo_delta_left).to eq(0)
      expect(result.match.elo_delta_right).to eq(0)
    end

    it "consumes the seed (replay-proof)" do
      seed = issue_pair_seed
      first = described_class.call(user: user, pair_seed: seed, winner_slug: left.slug)
      second = described_class.call(user: user, pair_seed: seed, winner_slug: right.slug)
      expect(first.success?).to be(true)
      expect(second.success?).to be(false)
      expect(second.error).to eq("seed_invalid_or_consumed")
    end
  end

  describe "failure paths" do
    it "fails on missing pair_seed" do
      result = described_class.call(user: user, pair_seed: "", winner_slug: left.slug)
      expect(result.success?).to be(false)
    end

    it "fails when winner_slug is not in the pair" do
      seed = issue_pair_seed
      stranger = create(:codex_node, realm: realm)
      result = described_class.call(user: user, pair_seed: seed, winner_slug: stranger.slug)
      expect(result.success?).to be(false)
      expect(result.error).to eq("winner_not_in_pair")
    end

    it "fails when seed user does not match caller" do
      seed = issue_pair_seed
      attacker = create(:user)
      result = described_class.call(user: attacker, pair_seed: seed, winner_slug: left.slug)
      expect(result.success?).to be(false)
      expect(result.error).to eq("seed_user_mismatch")
    end

    it "fails when the caller user is not persisted" do
      unsaved = build(:user)
      result = described_class.call(user: unsaved, pair_seed: "anything", winner_slug: left.slug)
      expect(result.success?).to be(false)
      expect(result.error).to eq("user is required")
    end

    it "fails when the seed references a node id that no longer exists" do
      seed = issue_pair_seed
      left.destroy!
      result = described_class.call(user: user, pair_seed: seed, winner_slug: right.slug)
      expect(result.success?).to be(false)
      expect(result.error).to eq("nodes_missing")
    end

    it "treats Redis outages during seed lookup as seed_invalid" do
      seed = "x" * 64
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:call).and_raise(StandardError, "redis down")
      allow(Kredis).to receive(:redis).with(config: :shared).and_return(fake_redis)
      allow(Rails.logger).to receive(:warn)

      result = described_class.call(user: user, pair_seed: seed, winner_slug: left.slug)
      expect(result.success?).to be(false)
      expect(result.error).to eq("seed_invalid_or_consumed")
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/redis unavailable/))
    end

    it "wraps an unexpected Match save failure into a Result failure" do
      seed = issue_pair_seed
      allow(Codex::Match).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(
          Codex::Match.new.tap { |m| m.errors.add(:base, "boom") }
        ))

      result = described_class.call(user: user, pair_seed: seed, winner_slug: left.slug)
      expect(result.success?).to be(false)
      expect(result.error).to include("boom")
    end
  end

  describe "winner resolution edge cases" do
    it "records the right node as winner when winner_slug matches right" do
      seed = issue_pair_seed
      result = described_class.call(user: user, pair_seed: seed, winner_slug: right.slug)
      expect(result.success?).to be(true)
      expect(result.match.winner_node_id).to eq(right.id)
      expect(result.match.elo_delta_right).to be > 0
    end

    it "records a skip match when winner_slug is nil without an explicit skip flag" do
      seed = issue_pair_seed
      result = described_class.call(user: user, pair_seed: seed, winner_slug: nil)

      expect(result.success?).to be(true)
      expect(result.match.winner_node_id).to be_nil
      expect(result.match.elo_delta_left).to eq(0)
      expect(result.match.elo_delta_right).to eq(0)
    end
  end

  describe "guard clauses" do
    it "returns failure when the user is nil" do
      result = described_class.call(user: nil, pair_seed: "any-seed")

      expect(result.success?).to be(false)
      expect(result.error).to eq("user is required")
    end
  end
end

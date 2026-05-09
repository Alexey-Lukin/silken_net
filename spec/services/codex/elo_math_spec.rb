# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::EloMath do
  describe ".expected" do
    it "returns 0.5 for equal Elos" do
      expect(described_class.expected(1500, 1500)).to be_within(1e-9).of(0.5)
    end

    it "favours the higher-rated side" do
      expect(described_class.expected(1700, 1500)).to be > 0.6
      expect(described_class.expected(1500, 1700)).to be < 0.4
    end
  end

  describe ".deltas" do
    it "is zero-sum" do
      d_l, d_r = described_class.deltas(left_elo: 1500, right_elo: 1500, winner: :left)
      expect(d_l + d_r).to eq(0)
    end

    it "rewards an upset more than a coin-flip win" do
      underdog_win, _ = described_class.deltas(left_elo: 1300, right_elo: 1700, winner: :left)
      expected_win, _ = described_class.deltas(left_elo: 1700, right_elo: 1300, winner: :left)
      expect(underdog_win).to be > expected_win
    end

    it "punishes an upset on the losing side" do
      _, d_r = described_class.deltas(left_elo: 1700, right_elo: 1300, winner: :right)
      # right was 1300 vs 1700 favourite → big positive delta for them
      expect(d_r).to be > 16
    end

    it "halves K once both nodes are past the decay threshold" do
      d_fresh, _ = described_class.deltas(
        left_elo: 1500, right_elo: 1500, winner: :left,
        match_count_left: 0, match_count_right: 0
      )
      d_decay, _ = described_class.deltas(
        left_elo: 1500, right_elo: 1500, winner: :left,
        match_count_left: 31, match_count_right: 31
      )
      expect(d_decay).to be < d_fresh
      expect(d_decay).to eq(described_class::K_DECAY / 2)
    end

    it "raises on bad winner" do
      expect {
        described_class.deltas(left_elo: 1500, right_elo: 1500, winner: :nobody)
      }.to raise_error(ArgumentError)
    end
  end
end

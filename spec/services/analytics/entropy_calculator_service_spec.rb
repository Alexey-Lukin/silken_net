# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::EntropyCalculatorService do
  describe ".call" do
    context "with insufficient data" do
      it "returns nil for empty array" do
        expect(described_class.call([])).to be_nil
      end

      it "returns nil for array smaller than MIN_SAMPLE_SIZE" do
        values = Array.new(29) { rand(2.0..45.0) }
        expect(described_class.call(values)).to be_nil
      end

      it "returns nil for nil input" do
        expect(described_class.call(nil)).to be_nil
      end
    end

    context "with valid data" do
      it "returns a Float between 0.0 and 1.0" do
        values = Array.new(100) { rand(2.0..45.0) }
        result = described_class.call(values)

        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 1.0)
      end

      it "returns exactly MIN_SAMPLE_SIZE threshold" do
        values = Array.new(30) { rand(2.0..45.0) }
        result = described_class.call(values)

        expect(result).to be_a(Float)
      end
    end

    context "entropy semantics" do
      it "returns 0.0 for all identical values (total order/stress)" do
        values = Array.new(100, 29.0)
        result = described_class.call(values)

        expect(result).to eq(0.0)
      end

      it "returns 1.0 for uniformly distributed values across full range" do
        # 200 values evenly spaced across [2.0, 45.0]
        values = (0...200).map { |i| 2.0 + (43.0 * i / 199.0) }
        result = described_class.call(values)

        expect(result).to eq(1.0)
      end

      it "returns low entropy for values clustered in a narrow band" do
        # All values within ±1.0 of 29.0 — occupies only 1 bin out of 20
        values = Array.new(100) { 29.0 + rand(-1.0..1.0) }
        result = described_class.call(values)

        expect(result).to be < 0.2
      end

      it "distinguishes healthy from stressed distributions" do
        # Healthy: diverse Z-values across the homeostasis range
        healthy = Array.new(200) { rand(5.0..42.0) }
        healthy_entropy = described_class.call(healthy)

        # Stressed: all values clustered in narrow band (occupies ~1 bin)
        stressed = Array.new(200) { 29.0 + rand(-1.0..1.0) }
        stressed_entropy = described_class.call(stressed)

        expect(healthy_entropy).to be > 0.8
        expect(stressed_entropy).to be < 0.2
        expect(healthy_entropy).to be > stressed_entropy
      end
    end

    context "edge cases" do
      it "handles negative Z-values" do
        values = Array.new(50) { rand(-10.0..10.0) }
        result = described_class.call(values)

        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 1.0)
      end

      it "handles very large Z-values" do
        values = Array.new(50) { rand(100.0..1000.0) }
        result = described_class.call(values)

        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 1.0)
      end

      it "filters out non-numeric values" do
        values = Array.new(50) { rand(2.0..45.0) } + [ nil, "bad", Float::NAN, Float::INFINITY ]
        result = described_class.call(values)

        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 1.0)
      end

      it "is deterministic (same input → same output)" do
        values = (1..100).map { |i| 2.0 + (i * 0.43) }
        a = described_class.call(values)
        b = described_class.call(values)

        expect(a).to eq(b)
      end

      it "returns result rounded to 4 decimal places" do
        values = Array.new(100) { rand(2.0..45.0) }
        result = described_class.call(values)

        expect(result.to_s.split(".").last.length).to be <= 4
      end
    end
  end

  describe "constants" do
    it "has MIN_SAMPLE_SIZE of 30" do
      expect(described_class::MIN_SAMPLE_SIZE).to eq(30)
    end

    it "has NUM_BINS of 20" do
      expect(described_class::NUM_BINS).to eq(20)
    end

    it "has BIN_RANGE matching Lorenz Z homeostasis zone" do
      expect(described_class::BIN_RANGE_MIN).to eq(2.0)
      expect(described_class::BIN_RANGE_MAX).to eq(45.0)
    end
  end
end

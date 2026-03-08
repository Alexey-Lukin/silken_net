# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::Attractor do
  describe ".calculate_z" do
    it "returns a finite Float" do
      result = described_class.calculate_z(123_456, 22.5, 5)
      expect(result).to be_a(Float)
      expect(result).to be_finite
    end

    it "is deterministic (same inputs → same output)" do
      a = described_class.calculate_z(42, 20.0, 10)
      b = described_class.calculate_z(42, 20.0, 10)
      expect(a).to eq(b)
    end

    it "produces different results for different seeds" do
      a = described_class.calculate_z(1, 22.0, 5)
      b = described_class.calculate_z(99_999, 22.0, 5)
      expect(a).not_to eq(b)
    end

    it "produces different results for different temperatures" do
      a = described_class.calculate_z(42, 10.0, 5)
      b = described_class.calculate_z(42, 50.0, 5)
      expect(a).not_to eq(b)
    end

    it "handles extreme temperature values without diverging" do
      result = described_class.calculate_z(42, 200.0, 5)
      expect(result).to be_finite
    end

    it "handles extreme acoustic values without diverging" do
      result = described_class.calculate_z(42, 22.0, 500)
      expect(result).to be_finite
    end

    it "handles zero seed" do
      result = described_class.calculate_z(0, 22.0, 5)
      expect(result).to be_a(Float)
      expect(result).to be_finite
    end
  end

  describe ".homeostatic?" do
    it "returns true when z_value is within family bounds" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      expect(described_class.homeostatic?(25.0, family)).to be true
    end

    it "returns false when z_value is below critical_z_min" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      expect(described_class.homeostatic?(3.0, family)).to be false
    end

    it "returns false when z_value is above critical_z_max" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      expect(described_class.homeostatic?(50.0, family)).to be false
    end

    it "returns true at boundary values" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      expect(described_class.homeostatic?(5.0, family)).to be true
      expect(described_class.homeostatic?(45.0, family)).to be true
    end
  end

  describe ".generate_trajectory" do
    it "returns a flat array of Float values" do
      trajectory = described_class.generate_trajectory(42, 22.0, 5)

      expect(trajectory).to be_an(Array)
      expect(trajectory).to all(be_a(Float))
    end

    it "returns exactly ITERATIONS * 3 elements (x, y, z per iteration)" do
      trajectory = described_class.generate_trajectory(42, 22.0, 5)
      expect(trajectory.size).to eq(SilkenNet::Attractor::ITERATIONS * 3)
    end

    it "all values are finite (no divergence)" do
      trajectory = described_class.generate_trajectory(42, 22.0, 5)
      expect(trajectory).to all(be_finite)
    end

    it "is deterministic" do
      a = described_class.generate_trajectory(42, 22.0, 5)
      b = described_class.generate_trajectory(42, 22.0, 5)
      expect(a).to eq(b)
    end
  end

  describe "constants" do
    it "has valid sigma limits" do
      expect(SilkenNet::Attractor::SIGMA_LIMITS).to be_a(Range)
      expect(SilkenNet::Attractor::SIGMA_LIMITS.min).to be > 0
    end

    it "has valid rho limits" do
      expect(SilkenNet::Attractor::RHO_LIMITS).to be_a(Range)
      expect(SilkenNet::Attractor::RHO_LIMITS.min).to be > 0
    end

    it "uses BigDecimal for base constants" do
      expect(SilkenNet::Attractor::BASE_SIGMA).to be_a(BigDecimal)
      expect(SilkenNet::Attractor::BASE_RHO).to be_a(BigDecimal)
      expect(SilkenNet::Attractor::BASE_BETA).to be_a(BigDecimal)
    end
  end
end

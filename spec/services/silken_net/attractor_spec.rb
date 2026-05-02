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

    it "uses Float for base constants (identical to firmware mruby)" do
      expect(SilkenNet::Attractor::BASE_SIGMA).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_RHO).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_BETA).to be_a(Float)
    end

    it "has DT of 0.01 (Float)" do
      expect(SilkenNet::Attractor::DT).to eq(0.01)
    end

    it "runs 250 iterations" do
      expect(SilkenNet::Attractor::ITERATIONS).to eq(250)
    end

    it "has BASE_BETA equal to IEEE 754 8.0/3.0" do
      expect(SilkenNet::Attractor::BASE_BETA).to eq(8.0 / 3.0)
    end
  end

  describe "clamping behavior" do
    it "clamps sigma within SIGMA_LIMITS for extreme acoustic values" do
      # With acoustic=1000, sigma would be 10 + 1000*0.1 = 110, clamped to 30
      z_extreme = described_class.calculate_z(42, 22.0, 1000)
      z_normal = described_class.calculate_z(42, 22.0, 5)
      # Both should be finite; extreme should differ from normal
      expect(z_extreme).to be_finite
      expect(z_extreme).not_to eq(z_normal)
    end

    it "clamps rho within RHO_LIMITS for extreme temperature values" do
      # With temp=500, rho would be 28 + 500*0.2 = 128, clamped to 50
      z_extreme = described_class.calculate_z(42, 500.0, 5)
      z_normal = described_class.calculate_z(42, 22.0, 5)
      expect(z_extreme).to be_finite
      expect(z_extreme).not_to eq(z_normal)
    end

    it "handles negative temperature (sub-zero)" do
      result = described_class.calculate_z(42, -40.0, 5)
      expect(result).to be_a(Float)
      expect(result).to be_finite
    end

    it "handles zero acoustic value" do
      result = described_class.calculate_z(42, 22.0, 0)
      expect(result).to be_a(Float)
      expect(result).to be_finite
    end

    it "handles very large seed values" do
      result = described_class.calculate_z(2**31 - 1, 22.0, 5)
      expect(result).to be_a(Float)
      expect(result).to be_finite
    end
  end

  describe "trajectory coordinate cycling" do
    it "returns x, y, z values at correct positions in trajectory" do
      trajectory = described_class.generate_trajectory(42, 22.0, 5)

      # Verify the array contains groups of x, y, z
      expect(trajectory.size).to eq(SilkenNet::Attractor::ITERATIONS * 3)

      # Every element at index % 3 == 0 is x, == 1 is y, == 2 is z
      # All should be finite floats rounded to 4 decimals
      trajectory.each_with_index do |val, i|
        expect(val).to be_a(Float)
        expect(val).to be_finite
      end
    end
  end

  describe "Dual Computation Integrity (firmware parity)" do
    # [FW.7] Backend MUST produce identical Z-values to firmware (mruby bio_contract.rb).
    # [FW.5] β perturbation from delta_t/vcap mirrored exactly.
    # This test replicates the exact firmware math to verify parity.
    def firmware_z(seed, temp, acoustic, delta_t_s = 60, vcap_mv = 3300)
      x = ((seed % 1000) / 500.0) - 1.0
      y = (((seed >> 4) % 1000) / 500.0) - 1.0
      z = (((seed >> 8) % 1000) / 500.0) - 1.0

      sigma = [ 5.0, [ 30.0, 10.0 + (acoustic * 0.1) ].min ].max
      rho   = [ 10.0, [ 50.0, 28.0 + (temp * 0.2) ].min ].max

      # [FW.5] β perturbation
      dt_improvement = 60 - delta_t_s
      dt_improvement = 0 if dt_improvement < 0
      vcap_centered = vcap_mv - 3300
      beta = (8.0 / 3.0) + (dt_improvement * 0.0001) + (vcap_centered * 0.001)
      beta = [ 2.0, [ 4.0, beta ].min ].max

      250.times do
        dx = sigma * (y - x)
        dy = x * (rho - z) - y
        dz = (x * y) - (beta * z)
        x += dx * 0.01
        y += dy * 0.01
        z += dz * 0.01
      end
      z
    end

    it "matches firmware Z (round 4) for normal inputs (default metabolism)" do
      [ [ 123_456, 22.5, 5 ], [ 42, 20.0, 10 ], [ 77_777, 15.0, 3 ] ].each do |seed, temp, acoustic|
        fw = firmware_z(seed, temp, acoustic).round(4)
        be = described_class.calculate_z(seed, temp, acoustic)
        expect(be).to eq(fw), "Mismatch for seed=#{seed}, temp=#{temp}, acoustic=#{acoustic}: firmware=#{fw}, backend=#{be}"
      end
    end

    it "matches firmware Z for extreme inputs (default metabolism)" do
      [ [ 0, 0, 0 ], [ 999_999, -40.0, 255 ], [ 2**31 - 1, 60.0, 200 ] ].each do |seed, temp, acoustic|
        fw = firmware_z(seed, temp, acoustic).round(4)
        be = described_class.calculate_z(seed, temp, acoustic)
        expect(be).to eq(fw), "Mismatch for seed=#{seed}, temp=#{temp}, acoustic=#{acoustic}: firmware=#{fw}, backend=#{be}"
      end
    end

    it "[FW.5] matches firmware Z when β-perturbed by delta_t/vcap" do
      [
        [ 123_456, 22.5, 5,  30, 3500 ],   # fast charge, high vcap
        [ 42,      20.0, 10, 90, 3100 ],   # slower charge, low vcap
        [ 77_777,  15.0, 3,  60, 3300 ],   # baseline (β unchanged)
        [ 555,     -10.0, 50, 5, 4200 ],   # extreme high — β clamped
        [ 999,     35.0,  120, 120, 1500 ] # extreme low — β clamped
      ].each do |seed, temp, acoustic, dt_s, vcap|
        fw = firmware_z(seed, temp, acoustic, dt_s, vcap).round(4)
        be = described_class.calculate_z(seed, temp, acoustic, dt_s, vcap)
        expect(be).to eq(fw),
          "Mismatch for seed=#{seed}, temp=#{temp}, acoustic=#{acoustic}, " \
          "dt_s=#{dt_s}, vcap=#{vcap}: firmware=#{fw}, backend=#{be}"
      end
    end

    it "[FW.5] firmware-vs-backend Z divergence < 1% across 500 random fuzz cases" do
      rng = Random.new(20_260_502)
      mismatches = 0
      500.times do
        seed     = rng.rand(0..(2**31 - 1))
        temp     = rng.rand(-40.0..60.0)
        acoustic = rng.rand(0..255)
        dt_s     = rng.rand(0..240)
        vcap     = rng.rand(2_000..4_500)

        fw = firmware_z(seed, temp, acoustic, dt_s, vcap).round(4)
        be = described_class.calculate_z(seed, temp, acoustic, dt_s, vcap)
        mismatches += 1 if (fw - be).abs > 0.0001
      end
      expect(mismatches).to eq(0),
        "Expected 0 firmware/backend mismatches across 500 fuzz cases, got #{mismatches}"
    end

    it "matches firmware bio_status category for boundary Z-values" do
      # Test that firmware and backend agree on homeostasis/stress/anomaly
      [ [ 1, 50.0, 200 ], [ 54_321, 10.0, 50 ], [ 100, 22.0, 5 ] ].each do |seed, temp, acoustic|
        fw_z = firmware_z(seed, temp, acoustic)
        be_z = described_class.calculate_z(seed, temp, acoustic).to_f

        fw_healthy = fw_z.between?(2.0, 45.0)
        be_healthy = be_z.between?(2.0, 45.0)

        expect(be_healthy).to eq(fw_healthy),
          "Category mismatch for seed=#{seed}: fw_z=#{fw_z.round(4)} (#{fw_healthy}), be_z=#{be_z} (#{be_healthy})"
      end
    end
  end

  describe "[FW.5] β-perturbation from EBFC metabolism" do
    it "perturb_beta returns classic 8/3 at baseline inputs" do
      expect(described_class.perturb_beta(60, 3300)).to eq(8.0 / 3.0)
    end

    it "increases β when EBFC charges faster than baseline" do
      # 30 s improvement → β += 30 * 0.0001 = +0.003
      expect(described_class.perturb_beta(30, 3300)).to be_within(1e-15).of((8.0 / 3.0) + 0.003)
    end

    it "ignores slower-than-baseline delta_t (no β decrease from delta_t alone)" do
      expect(described_class.perturb_beta(120, 3300)).to eq(8.0 / 3.0)
    end

    it "increases β when vcap is above nominal" do
      # +200 mV → β += 0.2
      expect(described_class.perturb_beta(60, 3500)).to be_within(1e-15).of((8.0 / 3.0) + 0.2)
    end

    it "decreases β when vcap is below nominal" do
      # -300 mV → β -= 0.3
      expect(described_class.perturb_beta(60, 3000)).to be_within(1e-15).of((8.0 / 3.0) - 0.3)
    end

    it "clamps β to BETA_LIMITS.max for extreme positive perturbation" do
      expect(described_class.perturb_beta(0, 5000)).to eq(SilkenNet::Attractor::BETA_LIMITS.max)
    end

    it "clamps β to BETA_LIMITS.min for extreme negative perturbation" do
      expect(described_class.perturb_beta(60, 0)).to eq(SilkenNet::Attractor::BETA_LIMITS.min)
    end

    it "calculate_z is sensitive to delta_t/vcap inputs (changes Z trajectory)" do
      z_baseline = described_class.calculate_z(42, 20.0, 5, 60, 3300)
      z_fast = described_class.calculate_z(42, 20.0, 5, 10, 3500)
      expect(z_fast).not_to eq(z_baseline)
    end

    it "calculate_z stays finite under extreme metabolism inputs" do
      result = described_class.calculate_z(42, 20.0, 5, 0, 65_535)
      expect(result).to be_finite
    end

    it "calculate_z_continued is sensitive to delta_t/vcap inputs" do
      base = described_class.calculate_z_continued(0.1, 0.2, 0.3, 20.0, 5, 60, 3300)
      fast = described_class.calculate_z_continued(0.1, 0.2, 0.3, 20.0, 5, 10, 3500)
      expect(fast.first).not_to eq(base.first)
    end
  end

  # [SEC.11] calculate_z_from_state — backend-side attractor entry-point
  # that mirrors the firmware Soldier when (x₀, y₀, z₀) come from K_seed
  # rather than from chaos_seed/DID. Same iteration kernel as
  # calculate_z_continued; separate spec section for documentation.
  describe ".calculate_z_from_state" do
    it "returns [z_rounded, x_final, y_final, z_final]" do
      result = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      expect(result).to be_an(Array)
      expect(result.size).to eq(4)
      result.each { |v| expect(v).to be_a(Float).and be_finite }
    end

    it "produces the same result as calculate_z_continued for identical inputs" do
      from_state = described_class.calculate_z_from_state(0.5, -0.5, 0.7, 22.0, 8, 45, 3450)
      continued  = described_class.calculate_z_continued(0.5, -0.5, 0.7, 22.0, 8, 45, 3450)
      expect(from_state).to eq(continued)
    end

    it "is sensitive to the initial state (different x₀ → different Z)" do
      a = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      b = described_class.calculate_z_from_state(0.9, 0.2, 0.3, 20.0, 5)
      expect(a.first).not_to eq(b.first)
    end

    it "stays finite under extreme metabolism inputs" do
      result = described_class.calculate_z_from_state(0.0, 0.0, 0.0, 25.0, 10, 0, 65_535)
      result.each { |v| expect(v).to be_finite }
    end

    it "is deterministic for the same (x0, y0, z0, temp, acoustic, delta_t, vcap)" do
      a = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      b = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      expect(a).to eq(b)
    end
  end
end

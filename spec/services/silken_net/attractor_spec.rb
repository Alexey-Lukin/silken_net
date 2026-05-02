# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::Attractor do
  # [SEC.11] Post-cutover the attractor takes initial (x₀, y₀, z₀)
  # directly — no `chaos_seed`, no DID-as-seed shortcut. The little
  # `xyz_for(seed)` helper is just a deterministic generator for test
  # input fixtures (mirrors firmware/test/test_bio_contract.c
  # `seed_to_xyz`); production code feeds (x₀, y₀, z₀) derived from
  # K_seed via SilkenNet::SeedDerivation.
  def xyz_for(seed)
    [
      ((seed % 1000) / 500.0) - 1.0,
      (((seed >> 4) % 1000) / 500.0) - 1.0,
      (((seed >> 8) % 1000) / 500.0) - 1.0
    ]
  end

  def calc_z(seed, temp, acoustic, dt = 60, vcap = 3300)
    x, y, z = xyz_for(seed)
    described_class.calculate_z_from_state(x, y, z, temp, acoustic, dt, vcap).first
  end

  describe ".calculate_z_from_state" do
    it "returns [z_rounded, x_final, y_final, z_final] of finite Floats" do
      result = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      expect(result).to be_an(Array)
      expect(result.size).to eq(4)
      result.each { |v| expect(v).to be_a(Float).and be_finite }
    end

    it "is deterministic for identical inputs" do
      a = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      b = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      expect(a).to eq(b)
    end

    it "is sensitive to the initial state — different x₀ → different Z" do
      a = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      b = described_class.calculate_z_from_state(0.9, 0.2, 0.3, 20.0, 5)
      expect(a.first).not_to eq(b.first)
    end

    it "is sensitive to temperature" do
      a = calc_z(42, 10.0, 5)
      b = calc_z(42, 50.0, 5)
      expect(a).not_to eq(b)
    end

    it "is sensitive to delta_t/vcap (β-perturbation)" do
      base = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 60, 3300)
      fast = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 10, 3500)
      expect(fast.first).not_to eq(base.first)
    end

    it "stays finite under extreme inputs" do
      [
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 200.0, 5),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 22.0, 500),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 25.0, 10, 0, 65_535),
        described_class.calculate_z_from_state(-1.0, -1.0, -1.0, -40.0, 0)
      ].each do |result|
        result.each { |v| expect(v).to be_finite }
      end
    end
  end

  describe ".homeostatic?" do
    let(:family) { build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0) }

    it "returns true when z_value is within family bounds" do
      expect(described_class.homeostatic?(25.0, family)).to be true
    end

    it "returns false when z_value is below critical_z_min" do
      expect(described_class.homeostatic?(3.0, family)).to be false
    end

    it "returns false when z_value is above critical_z_max" do
      expect(described_class.homeostatic?(50.0, family)).to be false
    end

    it "returns true at boundary values (inclusive)" do
      expect(described_class.homeostatic?(5.0, family)).to be true
      expect(described_class.homeostatic?(45.0, family)).to be true
    end
  end

  describe ".generate_trajectory" do
    it "returns ITERATIONS * 3 finite Floats (flat x,y,z stream)" do
      trajectory = described_class.generate_trajectory(0.0, 0.0, 0.0, 22.0, 5)
      expect(trajectory.size).to eq(SilkenNet::Attractor::ITERATIONS * 3)
      expect(trajectory).to all(be_a(Float).and(be_finite))
    end

    it "is deterministic for identical inputs" do
      a = described_class.generate_trajectory(0.1, 0.2, 0.3, 22.0, 5)
      b = described_class.generate_trajectory(0.1, 0.2, 0.3, 22.0, 5)
      expect(a).to eq(b)
    end
  end

  describe "constants" do
    it "exposes Float-only base constants (firmware mruby parity)" do
      expect(SilkenNet::Attractor::BASE_SIGMA).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_RHO).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_BETA).to be_a(Float)
    end

    it "BASE_BETA == IEEE-754 8.0/3.0 (bit-identical to firmware)" do
      expect(SilkenNet::Attractor::BASE_BETA).to eq(8.0 / 3.0)
    end

    it "DT == 0.01 and ITERATIONS == 250" do
      expect(SilkenNet::Attractor::DT).to eq(0.01)
      expect(SilkenNet::Attractor::ITERATIONS).to eq(250)
    end

    it "exposes σ/ρ Range clamps" do
      expect(SilkenNet::Attractor::SIGMA_LIMITS).to be_a(Range)
      expect(SilkenNet::Attractor::RHO_LIMITS).to be_a(Range)
    end
  end

  describe "Dual Computation Integrity (firmware parity)" do
    # [SEC.11] Backend MUST produce identical Z-values to firmware
    # mruby for the same (x₀, y₀, z₀, temp, acoustic, delta_t, vcap).
    # This local re-impl is the canonical kernel — if backend ever
    # drifts, this fuzz test catches it. Mirror of
    # firmware/bio_contracts/bio_contract.rb#iterate.
    def firmware_z(x, y, z, temp, acoustic, delta_t_s = 60, vcap_mv = 3300)
      sigma = [ 5.0, [ 30.0, 10.0 + (acoustic * 0.1) ].min ].max
      rho   = [ 10.0, [ 50.0, 28.0 + (temp * 0.2) ].min ].max

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

    it "matches firmware Z bit-by-bit on a 200-case fuzz sweep" do
      rng = Random.new(20_260_502)
      mismatches = []
      200.times do
        x0   = rng.rand(-1.0..1.0)
        y0   = rng.rand(-1.0..1.0)
        z0   = rng.rand(-1.0..1.0)
        temp = rng.rand(-40.0..60.0)
        ac   = rng.rand(0..255)
        dt_s = rng.rand(0..240)
        vcap = rng.rand(2_000..4_500)

        fw = firmware_z(x0, y0, z0, temp, ac, dt_s, vcap).round(4)
        be = described_class.calculate_z_from_state(x0, y0, z0, temp, ac, dt_s, vcap).first
        mismatches << [ x0, y0, z0, temp, ac, dt_s, vcap, fw, be ] if (fw - be).abs > 1e-9
      end
      expect(mismatches).to be_empty,
        "Firmware/backend Z divergence on #{mismatches.size}/200 cases. First: #{mismatches.first}"
    end

    it "matches firmware bio_status category for boundary Z-values" do
      [ [ 1, 50.0, 200 ], [ 54_321, 10.0, 50 ], [ 100, 22.0, 5 ] ].each do |seed, temp, acoustic|
        x, y, z = xyz_for(seed)
        fw_z = firmware_z(x, y, z, temp, acoustic)
        be_z = described_class.calculate_z_from_state(x, y, z, temp, acoustic).first.to_f

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
      expect(described_class.perturb_beta(30, 3300)).to be_within(1e-15).of((8.0 / 3.0) + 0.003)
    end

    it "ignores slower-than-baseline delta_t (β floor on Δt alone)" do
      expect(described_class.perturb_beta(120, 3300)).to eq(8.0 / 3.0)
    end

    it "increases β when vcap is above nominal" do
      expect(described_class.perturb_beta(60, 3500)).to be_within(1e-15).of((8.0 / 3.0) + 0.2)
    end

    it "decreases β when vcap is below nominal" do
      expect(described_class.perturb_beta(60, 3000)).to be_within(1e-15).of((8.0 / 3.0) - 0.3)
    end

    it "clamps β to BETA_LIMITS.max for extreme positive perturbation" do
      expect(described_class.perturb_beta(0, 5000)).to eq(SilkenNet::Attractor::BETA_LIMITS.max)
    end

    it "clamps β to BETA_LIMITS.min for extreme negative perturbation" do
      expect(described_class.perturb_beta(60, 0)).to eq(SilkenNet::Attractor::BETA_LIMITS.min)
    end
  end
end

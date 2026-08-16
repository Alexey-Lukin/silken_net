# SPDX-License-Identifier: AGPL-3.0-or-later
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
      expect(result).to all(be_a(Float).and(be_finite))
    end

    it "is deterministic for identical inputs" do
      a = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      b = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      expect(a).to eq(b)
    end

    it "still computes when SilkenNet::Metrics is undefined (defined?-guarded observe)" do
      hide_const("SilkenNet::Metrics")
      result = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      expect(result).to all(be_a(Float).and(be_finite))
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

    it "[E.63] is INDEPENDENT of delta_t/vcap — metabolism no longer perturbs β/Z" do
      # Lorenz is now a pure chaos gate (β = BASE_BETA). Metabolism sets
      # growth_points directly on-device (firmware BioContract), so Z must
      # NOT move with delta_t/vcap — decoupled. 00_07 E.63.
      base = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 60, 3300)
      fast = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 10, 3500)
      slow = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 7200, 2800)
      expect(fast.first).to eq(base.first)
      expect(slow.first).to eq(base.first)
    end

    it "stays finite under extreme inputs" do
      results = [
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 200.0, 5),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 22.0, 500),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 25.0, 10, 0, 65_535),
        described_class.calculate_z_from_state(-1.0, -1.0, -1.0, -40.0, 0)
      ]
      expect(results.flatten).to all(be_finite)
    end
  end

  describe ".homeostatic? [E.64 ρ-relative anomaly ceiling]" do
    let(:family) { build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0) }

    it "returns true when z within bounds (temp=0 → ρ=28 → ceiling=45)" do
      expect(described_class.homeostatic?(25.0, family, 0.0)).to be true
    end

    it "returns false below critical_z_min (absolute stress floor)" do
      expect(described_class.homeostatic?(3.0, family, 0.0)).to be false
    end

    it "returns false above the ρ-relative anomaly ceiling (temp=0 → 45)" do
      expect(described_class.homeostatic?(50.0, family, 0.0)).to be false
    end

    it "returns true at boundary values (inclusive, temp=0)" do
      expect(described_class.homeostatic?(5.0, family, 0.0)).to be true
      expect(described_class.homeostatic?(45.0, family, 0.0)).to be true
    end

    it "[E.64] warm temp raises the ceiling — z=50 anomaly@temp=0, homeostatic@temp=60" do
      # temp=60 → ρ=40 → ceiling = 40 + (45-28) = 57; z=50 < 57 → homeostatic (not a warm-day false anomaly)
      expect(described_class.homeostatic?(50.0, family, 0.0)).to be false
      expect(described_class.homeostatic?(50.0, family, 60.0)).to be true
    end

    it "[E.64] anomaly_ceiling preserves critical_z_max at ρ=BASE_RHO (temp=0)" do
      expect(described_class.anomaly_ceiling(0.0, 45.0)).to be_within(1e-9).of(45.0)
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

  describe "Dual Computation Integrity (REAL firmware contract — subprocess)" do
    # [FW.57 F4] The firmware contract (firmware/bio_contracts/bio_contract.rb)
    # defines its OWN SilkenNet::Attractor, so it can't be co-loaded with the
    # backend in one process. We run it in an isolated subprocess and compare its
    # output DIRECTLY to the backend mirror — replacing the old hand-copied
    # `firmware_z` (a 3rd kernel copy that could silently drift while both
    # "parity" sides still agreed). Z + bio_status are compared; GP parity needs
    # a backend metabolic_health mirror (= B, deferred to FW.2 — 00_07 E.63).
    # NB: anomaly (z > ρ-relative ceiling) is rare by design (E.64) → the sweep
    # mostly exercises the homeostasis branch + the kernel Z parity.
    def run_firmware_contract(cases)
      runner = Rails.root.join("tools/firmware/contract_runner.rb").to_s
      out = IO.popen([ Gem.ruby, runner ], "r+") do |io|
        io.write(JSON.generate(cases: cases))
        io.close_write
        io.read
      end
      raise "contract_runner.rb failed (status #{$?.exitstatus}): #{out}" unless $?.success?
      JSON.parse(out)
    end

    it "matches the backend Z + bio_status on a 200-case fuzz sweep (real contract, not a mirror)" do
      fw_family = Struct.new(:critical_z_min, :critical_z_max).new(2.0, 45.0)
      rng = Random.new(20_260_502)
      cases = Array.new(200) do
        [ rng.rand(-1.0..1.0), rng.rand(-1.0..1.0), rng.rand(-1.0..1.0),
          rng.rand(-40.0..60.0), rng.rand(0..255), rng.rand(0..7200) ]
      end

      fw = run_firmware_contract(cases)
      z_div = []
      status_div = []

      cases.each_with_index do |(x, y, z, temp, ac, dt), i|
        fw_payload, fw_z = fw[i]
        be_z = described_class.calculate_z_from_state(x, y, z, temp, ac, dt)[3] # raw final Z

        z_div << [ i, fw_z, be_z ] if (fw_z - be_z).abs > 1e-9

        # firmware packs status into bits 6..5; the backend classifies with its
        # REAL homeostatic? / anomaly_ceiling (no hand-copied kernel logic).
        fw_status = (fw_payload >> 5) & 0x03
        agree =
          case fw_status
          when 0 then described_class.homeostatic?(be_z, fw_family, temp)
          when 1 then be_z < fw_family.critical_z_min                                        # stress
          when 2 then be_z > described_class.anomaly_ceiling(temp, fw_family.critical_z_max) # anomaly
          else true # tamper/VM-error not produced by evaluate_and_pack
          end
        status_div << [ i, fw_status, be_z.round(4), temp.round(1) ] unless agree
      end

      expect(z_div).to be_empty, "Z divergence (real fw ↔ backend): #{z_div.first(3)}"
      expect(status_div).to be_empty, "bio_status divergence (real fw ↔ backend): #{status_div.first(3)}"
    end
  end

  # [ARCH.102] Дзеркало сентинела «метаболізм не виміряно». Дім значення й
  # підстави — `firmware/bio_contracts/bio_contract.rb`; тут доводиться, що
  # DCI-звірка не оголосить розходженням саме чесну відмову пристрою.
  #
  # 🔴 Чому це money-path: доти guard-и wall-time і непрогріта EMA віддавали
  # `BASELINE_DELTA_T_S = 60`, а `metabolic_health(60)` = 1.08 → clamp 1.0 →
  # GP = `GP_HOMEO_MAX`. Тобто відмова виміряти нараховувала МАКСИМУМ балів,
  # які йдуть у `Wallet#credit!` і в `leaf0` тижневого L1-якоря.
  describe ".expected_homeostasis_gp" do
    it "credits nothing when the metabolism was not measured" do
      expect(described_class.expected_homeostasis_gp(described_class::DELTA_T_UNKNOWN_S)).to eq(0)
    end

    # ⊥ Ліхтар: сентинел не сміє зрізати ЖВАВІСТЬ. Виміряні 60 с — це дуже
    # швидкий перезаряд, і він і далі дає максимум; без цієї половини фікс
    # не відрізнити від «просто занизили бали».
    it "still peaks on a genuinely measured fast recharge" do
      expect(described_class.expected_homeostasis_gp(60)).to eq(described_class::GP_HOMEO_MAX)
    end

    it "keeps the measured band between the calibration thresholds" do
      expect(described_class.expected_homeostasis_gp(described_class::DELTA_T_SLOW_S))
        .to eq(described_class::GP_HOMEO_MIN)
    end
  end
end

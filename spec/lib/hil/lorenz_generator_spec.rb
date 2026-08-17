# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "hil/lorenz_generator"

RSpec.describe Hil::LorenzGenerator do
  # Pin the K_seed so every example sees byte-identical (x₀, y₀, z₀).
  # Lorenz iteration is deterministic past that point, so paired sensor
  # inputs always produce the same Z — no flaky fixtures.
  let(:seed_hex) { "A" * 64 }

  describe "#sample" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(11)) }

    it "returns the full input/output payload" do
      sample = generator.sample(state: :homeostasis)
      expect(sample).to include(
        :state, :temperature_c, :acoustic_events, :metabolism_s, :voltage_mv,
        :x0, :y0, :z0, :x_final, :y_final, :z_final, :z_value
      )
      expect(sample[:state]).to eq(:homeostasis)
    end

    it "is deterministic for a given seed + rng + state" do
      a = described_class.new(seed_hex: seed_hex, rng: Random.new(99)).sample(state: :homeostasis)
      b = described_class.new(seed_hex: seed_hex, rng: Random.new(99)).sample(state: :homeostasis)
      expect(a[:z_value]).to eq(b[:z_value])
    end

    it "honours overrides over state defaults" do
      sample = generator.sample(
        state: :homeostasis,
        temperature_c: 5, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300
      )
      expect(sample[:temperature_c]).to eq(5)
      expect(sample[:acoustic_events]).to eq(0)
      expect(sample[:metabolism_s]).to eq(60)
      expect(sample[:voltage_mv]).to eq(3300)
    end

    it "rejects unknown states" do
      expect { generator.sample(state: :euphoria) }
        .to raise_error(ArgumentError, /unknown state/)
    end

    # 🔴 [ARCH.102] Носій СЕМАНТИКИ дроту, а не форми константи. Прошивка
    # інкрементує `acoustic_events` лише на кавітації й пилці, тож здорове
    # дерево фізично не може віддати ненульовий лічильник — і саме це
    # порушував попередній `class → range` мапінг (`wind` давав 15..60 для
    # гомеостазу, тобто симулятор робив тихий ліс гучним). Пін на пару, бо
    # позитивна половина сама по собі не відрізнила б «регістр правильний»
    # від «генератор завжди мовчить».
    it "не видає детекцій для станів, які прошивка лишає тихими" do
      quiet = 40.times.map { |i| described_class.new(seed_hex: seed_hex, rng: Random.new(i)) }
                      .flat_map { |g| [ g.sample(state: :homeostasis), g.synthesize(state: :stress) ] }

      expect(quiet.map { |s| s[:acoustic_events] }.uniq).to eq([ 0 ])
    end

    it "видає детекції для аномалії — інакше попередній пін був би вакуумним" do
      loud = 40.times.map { |i| described_class.new(seed_hex: seed_hex, rng: Random.new(i)).synthesize(state: :anomaly) }

      expect(loud.map { |s| s[:acoustic_events] }).to all(be_positive)
    end

    it "agrees with SilkenNet::Attractor for the supplied inputs" do
      sample = generator.sample(
        state: :homeostasis,
        temperature_c: 20, acoustic_events: 30, metabolism_s: 50, voltage_mv: 3500
      )
      expected_z, = SilkenNet::Attractor.calculate_z_from_state(
        sample[:x0], sample[:y0], sample[:z0],
        20, 30, 50, 3500
      )
      expect(sample[:z_value]).to eq(expected_z)
    end
  end

  describe "#sample_in_state" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(7)) }

    it "lands a :homeostasis sample inside [z_min .. z_max]" do
      sample = generator.sample_in_state(state: :homeostasis)
      expect(sample[:z_value]).to be_between(
        described_class::DEFAULT_Z_MIN, described_class::DEFAULT_Z_MAX
      ).inclusive
    end

    it "refuses :stress with a helpful message (Lorenz dynamics unreachable)" do
      expect { generator.sample_in_state(state: :stress) }
        .to raise_error(ArgumentError, /only supports :homeostasis/)
    end

    it "refuses :anomaly with a helpful message (Lorenz dynamics unreachable)" do
      expect { generator.sample_in_state(state: :anomaly) }
        .to raise_error(ArgumentError, /only supports :homeostasis/)
    end

    context "with a custom TreeFamily" do
      subject(:generator) do
        described_class.new(tree_family: tree_family, seed_hex: seed_hex, rng: Random.new(3))
      end

      let(:tree_family) do
        build(:tree_family, critical_z_min: 10.0, critical_z_max: 35.0)
      end


      it "respects the family-specific z thresholds" do
        sample = generator.sample_in_state(state: :homeostasis)
        expect(sample[:z_value]).to be_between(10.0, 35.0).inclusive
      end
    end

    it "raises RuntimeError when max_attempts is exhausted without landing in band" do
      # Force an impossible band so rejection sampling can never succeed.
      family = build(:tree_family, critical_z_min: 9_999.0, critical_z_max: 10_000.0)
      gen = described_class.new(tree_family: family, seed_hex: seed_hex, rng: Random.new(13))
      expect { gen.sample_in_state(state: :homeostasis, max_attempts: 3) }
        .to raise_error(RuntimeError, /could not land in homeostasis band/)
    end
  end

  describe "#synthesize" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(5)) }

    it "forces :stress samples below z_min" do
      sample = generator.synthesize(state: :stress)
      expect(sample[:z_value]).to be < described_class::DEFAULT_Z_MIN
      expect(sample[:synthetic]).to be true
    end

    it "forces :anomaly samples above z_max" do
      sample = generator.synthesize(state: :anomaly)
      expect(sample[:z_value]).to be > described_class::DEFAULT_Z_MAX
      expect(sample[:synthetic]).to be true
    end

    it "syncs z_final with z_value so trajectory tails are consistent" do
      sample = generator.synthesize(state: :anomaly)
      expect(sample[:z_final]).to eq(sample[:z_value])
    end

    it "rejects :homeostasis (use #sample instead)" do
      expect { generator.synthesize(state: :homeostasis) }
        .to raise_error(ArgumentError, /only supports :stress or :anomaly/)
    end

    it "rejects unknown states with a helpful list of valid keys" do
      expect { generator.synthesize(state: :euphoria) }
        .to raise_error(ArgumentError, /unknown state :euphoria/)
    end
  end

  describe "#batch" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(2)) }

    it "returns N samples in the requested state" do
      batch = generator.batch(state: :homeostasis, count: 4)
      expect(batch.size).to eq(4)
      expect(batch).to all(include(state: :homeostasis))
    end

    it "routes :stress through synthesize automatically" do
      batch = generator.batch(state: :stress, count: 3)
      expect(batch.map { |s| s[:z_value] }).to all(be < described_class::DEFAULT_Z_MIN)
      expect(batch).to all(include(synthetic: true))
    end

    it "routes :anomaly through synthesize automatically" do
      batch = generator.batch(state: :anomaly, count: 2)
      expect(batch.map { |s| s[:z_value] }).to all(be > described_class::DEFAULT_Z_MAX)
    end

    it "routes in_band: true to sample_in_state for :homeostasis" do
      batch = generator.batch(state: :homeostasis, count: 2, in_band: true)
      expect(batch.size).to eq(2)
      expect(batch.map { |s| s[:z_value] }).to all(
        be_between(described_class::DEFAULT_Z_MIN, described_class::DEFAULT_Z_MAX).inclusive
      )
    end

    it "raises ArgumentError for unknown states" do
      expect { generator.batch(state: :euphoria, count: 1) }
        .to raise_error(ArgumentError, /unknown state :euphoria/)
    end
  end

  describe "#trajectory" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(0)) }

    it "produces a flat Float array of length ITERATIONS * 3" do
      traj = generator.trajectory(state: :homeostasis)
      expect(traj.size).to eq(SilkenNet::Attractor::ITERATIONS * 3)
      expect(traj).to all(be_a(Float))
    end
  end

  describe ".to_csv" do
    it "renders header + rows for an array of samples" do
      gen = described_class.new(seed_hex: seed_hex, rng: Random.new(0))
      samples = gen.batch(state: :homeostasis, count: 2)
      csv = described_class.to_csv(samples)
      lines = csv.lines
      expect(lines.first.chomp.split(",")).to eq(%w[
        state temperature_c acoustic_events metabolism_s voltage_mv
        x0 y0 z0 x_final y_final z_final z_value
      ])
      expect(lines.size).to eq(3) # header + 2 rows
    end

    it "returns empty string for empty input" do
      expect(described_class.to_csv([])).to eq("")
    end
  end

  describe "initialization" do
    it "validates seed length" do
      expect { described_class.new(seed_hex: "deadbeef") }
        .to raise_error(ArgumentError, /seed_hex must be 64 hex characters/)
    end

    it "accepts no explicit seed (random)" do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#in_band? (private band classifier)" do
    subject(:generator) { described_class.new(seed_hex: seed_hex, rng: Random.new(8)) }

    it "classifies z below the min threshold as stress" do
      expect(generator.send(:in_band?, 1.0, :stress)).to be(true)
    end

    it "classifies z above the max threshold as anomaly" do
      expect(generator.send(:in_band?, 99.0, :anomaly)).to be(true)
    end

    it "raises for an unknown state" do
      expect { generator.send(:in_band?, 10.0, :bogus) }
        .to raise_error(ArgumentError, /no Z band defined/)
    end
  end
end

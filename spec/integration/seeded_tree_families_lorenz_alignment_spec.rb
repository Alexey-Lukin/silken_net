# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Regression guard for the SSOT drift caught in the 2026-05-16 cross-doc
# audit (OPS.8): `db/seeds.rb` used to seed Pinus sylvestris with
# `critical_z_min: -2.5, critical_z_max: 2.5` and Quercus robur with
# `-3.0 .. 3.0`. Those bands predated the Lorenz attractor migration and
# made every Lorenz-derived Z (~9..50) fall outside homeostasis →
# `check_z_divergence!` fired on every packet and
# `OtaPackagerService` shipped a broken CMD_SET_THRESHOLDS payload.
#
# The seed file deletes every model on every run, so we cannot exercise
# it from a transactional spec. Instead we keep the canonical Z-band
# values in `EXPECTED_SEEDED_FAMILIES` below and lock them in lock-step
# with `db/seeds.rb`. If the seed is ever rolled back, this spec fails
# loudly before broken values land in a fresh deploy.
RSpec.describe "Seeded TreeFamily values vs Lorenz attractor (OPS.8)" do
  expected_seeded_families = [
    {
      name: "Сосна звичайна",
      scientific_name: "Pinus sylvestris",
      critical_z_min: 5.0,
      critical_z_max: 45.0,
      optimal_z_target: 29.0,
      carbon_sequestration_coefficient: 0.8
    },
    {
      name: "Дуб звичайний",
      scientific_name: "Quercus robur",
      critical_z_min: 8.0,
      critical_z_max: 40.0,
      optimal_z_target: 24.0,
      carbon_sequestration_coefficient: 1.5
    }
  ].freeze

  expected_seeded_families.each do |attrs|
    context "when seeding #{attrs[:scientific_name]} from `db/seeds.rb`" do
      subject(:family) { TreeFamily.create!(attrs) }

      it "is valid after persistence" do
        expect { family }.not_to raise_error
        expect(family).to be_persisted
      end

      it "classifies its own optimal_z_target as homeostatic" do
        expect(family.healthy_z?(attrs[:optimal_z_target])).to be true
        expect(SilkenNet::Attractor.homeostatic?(attrs[:optimal_z_target], family, 0.0)).to be true
      end

      it "classifies Z just above critical_z_max as non-homeostatic" do
        z = attrs[:critical_z_max] + 1.0
        expect(family.healthy_z?(z)).to be false
        expect(SilkenNet::Attractor.homeostatic?(z, family, 0.0)).to be false # [E.64] temp=0 → ceiling=critical_z_max
      end

      it "classifies Z just below critical_z_min as non-homeostatic" do
        z = attrs[:critical_z_min] - 1.0
        expect(family.healthy_z?(z)).to be false
        expect(SilkenNet::Attractor.homeostatic?(z, family, 0.0)).to be false # [E.64] temp=0 → ceiling=critical_z_max
      end

      it "covers the realistic Lorenz Z reach (≥ ρ_min−1 ≈ 9 .. ρ_max−1 ≈ 49)" do
        # If a future seed regression narrows the band back below ~9, the
        # band will not intersect the Lorenz attractor's natural reach and
        # every uplink will be flagged as anomaly. Guard against that.
        expect(attrs[:critical_z_min]).to be <= 10.0
        expect(attrs[:critical_z_max]).to be >= 30.0
      end

      it "keeps the global Lorenz envelope as outer bounds" do
        expect(attrs[:critical_z_min]).to be >= Tree::GLOBAL_LORENZ_Z_MIN
        expect(attrs[:critical_z_max]).to be <= Tree::GLOBAL_LORENZ_Z_MAX
        expect(attrs[:optimal_z_target]).to be_between(attrs[:critical_z_min], attrs[:critical_z_max])
      end
    end
  end

  context "with raw seed file content" do
    # The values block is the only literal definition of seeded families
    # in the repo. Spot-check that the seed source still carries the
    # values this spec asserts — catches a regression even before the
    # `TreeFamily.create!` example above runs.
    let(:seed_source) { File.read(Rails.root.join("db", "seeds.rb")) }

    it "writes Pinus sylvestris with the Lorenz-aligned band" do
      expect(seed_source).to match(/Pinus sylvestris.*?critical_z_min:\s*5\.0.*?critical_z_max:\s*45\.0.*?optimal_z_target:\s*29\.0/m)
    end

    it "writes Quercus robur with the tighter oak band" do
      expect(seed_source).to match(/Quercus robur.*?critical_z_min:\s*8\.0.*?critical_z_max:\s*40\.0.*?optimal_z_target:\s*24\.0/m)
    end
  end
end

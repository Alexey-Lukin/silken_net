# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::Attractor do
  describe ".calculate_z" do
    it "is deterministic for same inputs" do
      z1 = described_class.calculate_z(12345, 22.0, 5)
      z2 = described_class.calculate_z(12345, 22.0, 5)

      expect(z1).to eq(z2)
    end

    it "returns different values for different seeds" do
      z1 = described_class.calculate_z(12345, 22.0, 5)
      z2 = described_class.calculate_z(67890, 22.0, 5)

      expect(z1).not_to eq(z2)
    end

    it "returns a finite float" do
      z = described_class.calculate_z(42, 20.0, 3)

      expect(z).to be_a(Float)
      expect(z).to be_finite
    end
  end

  describe ".homeostatic?" do
    let(:tree_family) { create(:tree_family, :scots_pine) }

    it "returns true when z is within bounds" do
      z = (tree_family.critical_z_min + tree_family.critical_z_max) / 2.0

      expect(described_class.homeostatic?(z, tree_family)).to be true
    end

    it "returns false when z is below min" do
      expect(described_class.homeostatic?(tree_family.critical_z_min - 1.0, tree_family)).to be false
    end

    it "returns false when z is above max" do
      expect(described_class.homeostatic?(tree_family.critical_z_max + 1.0, tree_family)).to be false
    end
  end

  describe ".generate_trajectory" do
    it "returns a flat array of ITERATIONS * 3 floats" do
      trajectory = described_class.generate_trajectory(42, 20.0, 3)

      expect(trajectory.length).to eq(described_class::ITERATIONS * 3)
      expect(trajectory).to all(be_a(Float))
    end
  end
end

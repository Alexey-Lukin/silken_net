# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::GeoUtils do
  describe ".haversine_distance_m" do
    it "returns 0 for identical points" do
      distance = described_class.haversine_distance_m(49.4285, 32.0620, 49.4285, 32.0620)
      expect(distance).to be_within(0.01).of(0)
    end

    it "calculates known distance between Kyiv and Cherkasy (~160 km)" do
      # Kyiv: 50.4501, 30.5234; Cherkasy: 49.4285, 32.0620
      distance = described_class.haversine_distance_m(50.4501, 30.5234, 49.4285, 32.0620)
      expect(distance).to be_within(5000).of(155_000) # ~155 km ± 5 km
    end

    it "calculates a short distance within a forest sector (~1 km)" do
      # Two points ~1 km apart
      distance = described_class.haversine_distance_m(49.4285, 32.0620, 49.4375, 32.0620)
      expect(distance).to be_within(50).of(1000) # ~1 km ± 50 m
    end

    it "returns the same distance regardless of direction (symmetry)" do
      d1 = described_class.haversine_distance_m(49.0, 32.0, 50.0, 33.0)
      d2 = described_class.haversine_distance_m(50.0, 33.0, 49.0, 32.0)
      expect(d1).to be_within(0.01).of(d2)
    end

    it "handles equator to pole calculation" do
      # Equator to North Pole ≈ 10,007 km
      distance = described_class.haversine_distance_m(0.0, 0.0, 90.0, 0.0)
      expect(distance).to be_within(50_000).of(10_007_543)
    end

    it "handles negative coordinates (Southern Hemisphere)" do
      distance = described_class.haversine_distance_m(-33.8688, 151.2093, -37.8136, 144.9631)
      expect(distance).to be > 500_000 # Sydney to Melbourne > 500 km
    end

    it "handles antimeridian crossing" do
      # Points near the antimeridian (180° longitude)
      distance = described_class.haversine_distance_m(0.0, 179.0, 0.0, -179.0)
      expect(distance).to be_within(10_000).of(222_000) # ~222 km along equator
    end
  end

  describe "EARTH_RADIUS_M constant" do
    it "is the mean Earth radius in metres" do
      expect(SilkenNet::GeoUtils::EARTH_RADIUS_M).to eq(6_371_000.0)
    end
  end
end

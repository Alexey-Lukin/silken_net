# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeoLocatable do
  describe "validations" do
    # Тестуємо через Tree, яка включає GeoLocatable
    subject(:tree) { build(:tree) }

    it "accepts valid coordinates" do
      tree.latitude = 48.8566
      tree.longitude = 2.3522
      tree.valid?
      expect(tree.errors[:latitude]).to be_empty
      expect(tree.errors[:longitude]).to be_empty
    end

    it "allows nil coordinates" do
      tree.latitude = nil
      tree.longitude = nil
      tree.valid?
      expect(tree.errors[:latitude]).to be_empty
      expect(tree.errors[:longitude]).to be_empty
    end

    it "rejects latitude out of range" do
      tree.latitude = 91.0
      tree.valid?
      expect(tree.errors[:latitude]).to be_present
    end

    it "rejects latitude below range" do
      tree.latitude = -91.0
      tree.valid?
      expect(tree.errors[:latitude]).to be_present
    end

    it "rejects longitude out of range" do
      tree.longitude = 181.0
      tree.valid?
      expect(tree.errors[:longitude]).to be_present
    end

    it "rejects longitude below range" do
      tree.longitude = -181.0
      tree.valid?
      expect(tree.errors[:longitude]).to be_present
    end

    it "accepts boundary values" do
      tree.latitude = 90.0
      tree.longitude = 180.0
      tree.valid?
      expect(tree.errors[:latitude]).to be_empty
      expect(tree.errors[:longitude]).to be_empty

      tree.latitude = -90.0
      tree.longitude = -180.0
      tree.valid?
      expect(tree.errors[:latitude]).to be_empty
      expect(tree.errors[:longitude]).to be_empty
    end
  end

  describe "#geolocated?" do
    subject(:tree) { build(:tree) }

    it "returns true when both coordinates present" do
      tree.latitude = 50.45
      tree.longitude = 30.52
      expect(tree.geolocated?).to be true
    end

    it "returns false when latitude is nil" do
      tree.latitude = nil
      tree.longitude = 30.52
      expect(tree.geolocated?).to be false
    end

    it "returns false when longitude is nil" do
      tree.latitude = 50.45
      tree.longitude = nil
      expect(tree.geolocated?).to be false
    end

    it "returns false when both are nil" do
      tree.latitude = nil
      tree.longitude = nil
      expect(tree.geolocated?).to be false
    end
  end
end

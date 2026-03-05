# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceRecord, type: :model do
  before do
    allow(EcosystemHealingWorker).to receive(:perform_async)
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to maintainable (polymorphic)" do
      assoc = described_class.reflect_on_association(:maintainable)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:polymorphic]).to be true
    end

    it "belongs to ews_alert (optional)" do
      assoc = described_class.reflect_on_association(:ews_alert)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be true
    end

    it "has many attached photos" do
      expect(described_class.new).to respond_to(:photos)
    end
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines all action_type values with prefix" do
      record = build(:maintenance_record)
      expect(record).to respond_to(:action_type_installation?)
      expect(record).to respond_to(:action_type_inspection?)
      expect(record).to respond_to(:action_type_cleaning?)
      expect(record).to respond_to(:action_type_repair?)
      expect(record).to respond_to(:action_type_decommissioning?)
    end
  end

  # =========================================================================
  # VALIDATIONS — базові
  # =========================================================================
  describe "validations" do
    it "is valid with default factory" do
      expect(build(:maintenance_record)).to be_valid
    end

    it "requires action_type" do
      expect(build(:maintenance_record, action_type: nil)).not_to be_valid
    end

    it "requires performed_at" do
      expect(build(:maintenance_record, performed_at: nil)).not_to be_valid
    end

    it "requires notes" do
      expect(build(:maintenance_record, notes: nil)).not_to be_valid
    end

    it "requires notes to be at least 10 characters" do
      expect(build(:maintenance_record, notes: "Short")).not_to be_valid
    end

    it "rejects performed_at in the future" do
      expect(build(:maintenance_record, performed_at: 1.hour.from_now)).not_to be_valid
    end

    # -----------------------------------------------------------------------
    # OpEx Financial Tracking (Series C)
    # -----------------------------------------------------------------------
    describe "labor_hours" do
      it "allows nil" do
        expect(build(:maintenance_record, labor_hours: nil)).to be_valid
      end

      it "allows zero" do
        expect(build(:maintenance_record, labor_hours: 0)).to be_valid
      end

      it "allows positive value" do
        expect(build(:maintenance_record, labor_hours: 3.5)).to be_valid
      end

      it "rejects negative value" do
        record = build(:maintenance_record, labor_hours: -1)
        expect(record).not_to be_valid
        expect(record.errors[:labor_hours]).to be_present
      end
    end

    describe "parts_cost" do
      it "allows nil" do
        expect(build(:maintenance_record, parts_cost: nil)).to be_valid
      end

      it "allows zero" do
        expect(build(:maintenance_record, parts_cost: 0)).to be_valid
      end

      it "allows positive value" do
        expect(build(:maintenance_record, parts_cost: 250.50)).to be_valid
      end

      it "rejects negative value" do
        record = build(:maintenance_record, parts_cost: -10)
        expect(record).not_to be_valid
        expect(record.errors[:parts_cost]).to be_present
      end
    end

    # -----------------------------------------------------------------------
    # Hardware State Sync
    # -----------------------------------------------------------------------
    describe "hardware_verified" do
      it "defaults to false" do
        expect(described_class.new.hardware_verified).to be false
      end

      it "accepts true" do
        expect(build(:maintenance_record, :hardware_verified)).to be_valid
      end
    end

    # -----------------------------------------------------------------------
    # GPS Coordinates (anti-sofa-repair)
    # -----------------------------------------------------------------------
    describe "coordinates" do
      it "allows nil latitude and longitude" do
        expect(build(:maintenance_record, latitude: nil, longitude: nil)).to be_valid
      end

      it "is valid with GPS coordinates" do
        expect(build(:maintenance_record, :with_gps)).to be_valid
      end

      it "rejects latitude out of range" do
        record = build(:maintenance_record, latitude: 100.0, longitude: 32.0)
        expect(record).not_to be_valid
        expect(record.errors[:latitude]).to be_present
      end

      it "rejects longitude out of range" do
        record = build(:maintenance_record, latitude: 49.0, longitude: 200.0)
        expect(record).not_to be_valid
        expect(record.errors[:longitude]).to be_present
      end
    end

    # -----------------------------------------------------------------------
    # Evidence Protocol (Trust Protocol)
    # -----------------------------------------------------------------------
    describe "photos required for repair and installation" do
      it "is invalid for :repair without photos" do
        record = build(:maintenance_record, :repair)
        expect(record).not_to be_valid
        expect(record.errors[:photos]).to include(
          a_string_matching(/обов'язкові для типів 'repair' та 'installation'/)
        )
      end

      it "is invalid for :installation without photos" do
        record = build(:maintenance_record, :installation)
        expect(record).not_to be_valid
        expect(record.errors[:photos]).to include(
          a_string_matching(/обов'язкові для типів 'repair' та 'installation'/)
        )
      end

      it "does NOT require photos for :inspection" do
        expect(build(:maintenance_record, action_type: :inspection)).to be_valid
      end

      it "does NOT require photos for :cleaning" do
        expect(build(:maintenance_record, action_type: :cleaning)).to be_valid
      end

      it "does NOT require photos for :decommissioning" do
        expect(build(:maintenance_record, action_type: :decommissioning)).to be_valid
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".recent" do
      it "orders by performed_at descending" do
        old_record = create(:maintenance_record, performed_at: 2.days.ago)
        new_record = create(:maintenance_record, performed_at: 1.hour.ago)

        expect(described_class.recent.first).to eq(new_record)
        expect(described_class.recent.last).to eq(old_record)
      end
    end

    describe ".by_type" do
      it "filters by action_type" do
        inspection     = create(:maintenance_record, performed_at: 3.hours.ago)
        cleaning_record = create(:maintenance_record, action_type: :cleaning,
                                                      notes: "Cleaned solar panels on node carefully.")

        expect(described_class.by_type(:inspection)).to include(inspection)
        expect(described_class.by_type(:cleaning)).to include(cleaning_record)
        expect(described_class.by_type(:inspection)).not_to include(cleaning_record)
      end
    end

    describe ".hardware_verified" do
      it "returns only hardware_verified records" do
        verified   = create(:maintenance_record, :hardware_verified)
        unverified = create(:maintenance_record, hardware_verified: false)

        results = described_class.hardware_verified
        expect(results).to include(verified)
        expect(results).not_to include(unverified)
      end
    end

    describe ".with_gps" do
      it "returns only records with GPS coordinates" do
        with_gps    = create(:maintenance_record, :with_gps)
        without_gps = create(:maintenance_record)

        expect(described_class.with_gps).to include(with_gps)
        expect(described_class.with_gps).not_to include(without_gps)
      end
    end
  end

  # =========================================================================
  # METHODS
  # =========================================================================
  describe "#total_cost" do
    it "returns 0.0 when labor_hours and parts_cost are nil" do
      record = build(:maintenance_record, labor_hours: nil, parts_cost: nil)
      expect(record.total_cost).to eq(0.0)
    end

    it "calculates labor cost at base rate" do
      record = build(:maintenance_record, labor_hours: 2.0, parts_cost: nil)
      expected = 2.0 * MaintenanceRecord::LABOR_RATE_PER_HOUR
      expect(record.total_cost).to eq(expected)
    end

    it "adds parts_cost to labor cost" do
      record = build(:maintenance_record, labor_hours: 1.0, parts_cost: 300.0)
      expected = (1.0 * MaintenanceRecord::LABOR_RATE_PER_HOUR) + 300.0
      expect(record.total_cost).to eq(expected)
    end

    it "returns only parts_cost when labor_hours is nil" do
      record = build(:maintenance_record, labor_hours: nil, parts_cost: 150.0)
      expect(record.total_cost).to eq(150.0)
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "callbacks" do
    it "triggers EcosystemHealingWorker after create" do
      expect(EcosystemHealingWorker).to receive(:perform_async).with(kind_of(Integer))
      create(:maintenance_record)
    end
  end

  # =========================================================================
  # FACTORY
  # =========================================================================
  describe "factory" do
    it "creates a valid default record" do
      expect(build(:maintenance_record)).to be_valid
    end

    it "creates a valid record with GPS and cost" do
      expect(build(:maintenance_record, :with_gps, :with_cost)).to be_valid
    end

    it "creates a valid hardware_verified record" do
      expect(build(:maintenance_record, :hardware_verified)).to be_valid
    end
  end
end

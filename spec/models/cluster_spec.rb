# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cluster, type: :model do
  describe "#health_index" do
    it "returns the cached health_index value from the database" do
      cluster = create(:cluster, health_index: 0.85)
      expect(cluster.health_index).to eq(0.85)
    end

    it "returns 1.0 when health_index is nil" do
      cluster = create(:cluster, health_index: nil)
      expect(cluster.health_index).to eq(1.0)
    end
  end

  describe "#local_yesterday" do
    it "returns UTC yesterday when no timezone is set" do
      cluster = create(:cluster)
      expect(cluster.local_yesterday).to eq(Time.current.utc.to_date - 1)
    end

    it "uses the cluster timezone when set" do
      cluster = create(:cluster, environmental_settings: { "timezone" => "Pacific/Auckland" })
      nz_yesterday = Time.use_zone("Pacific/Auckland") { Date.yesterday }
      expect(cluster.local_yesterday).to eq(nz_yesterday)
    end

    it "falls back to UTC when timezone is empty string" do
      cluster = create(:cluster, environmental_settings: { "timezone" => "" })
      expect(cluster.local_yesterday).to eq(Time.current.utc.to_date - 1)
    end
  end

  describe "#recalculate_health_index!" do
    it "accepts a target_date parameter" do
      cluster = create(:cluster)
      result = cluster.recalculate_health_index!(Time.current.utc.to_date - 1)
      expect(result).to eq(1.0) # No insights → default 1.0
    end
  end

  describe "#total_active_trees" do
    it "returns the cached active_trees_count column value" do
      cluster = create(:cluster, active_trees_count: 42)
      expect(cluster.total_active_trees).to eq(42)
    end

    it "defaults to 0 for a new cluster" do
      cluster = create(:cluster)
      expect(cluster.total_active_trees).to eq(0)
    end
  end

  describe "#active_contract" do
    it "returns the most recently created active contract" do
      cluster = create(:cluster)
      older = create(:naas_contract, cluster: cluster, status: :active, created_at: 2.days.ago)
      newer = create(:naas_contract, cluster: cluster, status: :active, created_at: 1.day.ago)

      expect(cluster.active_contract).to eq(newer)
    end

    it "returns nil when no active contracts exist" do
      cluster = create(:cluster)
      create(:naas_contract, cluster: cluster, status: :draft)

      expect(cluster.active_contract).to be_nil
    end
  end

  describe "#geo_center" do
    it "returns nil when geojson_polygon is absent" do
      cluster = create(:cluster, geojson_polygon: nil)
      expect(cluster.geo_center).to be_nil
    end

    it "calculates centroid from Polygon coordinates" do
      polygon = {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
      cluster = create(:cluster, geojson_polygon: polygon)
      center = cluster.geo_center

      expect(center[:lng]).to be_within(0.01).of(31.94)
      expect(center[:lat]).to be_within(0.01).of(49.44)
    end

    it "memoizes the result across multiple calls" do
      polygon = {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
      cluster = create(:cluster, geojson_polygon: polygon)

      first_call = cluster.geo_center
      second_call = cluster.geo_center

      expect(first_call).to equal(second_call) # same object_id (memoized)
    end
  end

  describe "#active_threats?" do
    it "returns true when cluster has unresolved critical alerts" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :active, severity: :critical, alert_type: :fire_detected)

      expect(cluster).to be_active_threats
    end

    it "returns false when cluster has no alerts" do
      cluster = create(:cluster)
      expect(cluster).not_to be_active_threats
    end

    it "returns false when alerts are resolved" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :resolved, severity: :critical, alert_type: :fire_detected)

      expect(cluster).not_to be_active_threats
    end

    it "returns false when alerts are not critical" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :active, severity: :low, alert_type: :severe_drought)

      expect(cluster).not_to be_active_threats
    end
  end

  describe "#mapped?" do
    it "returns true when geojson_polygon has coordinates" do
      polygon = { "type" => "Polygon", "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.5 ] ] ] }
      cluster = build(:cluster, geojson_polygon: polygon)

      expect(cluster).to be_mapped
    end

    it "returns false when geojson_polygon is nil" do
      cluster = build(:cluster, geojson_polygon: nil)
      expect(cluster).not_to be_mapped
    end

    it "returns false when coordinates are missing" do
      cluster = build(:cluster, geojson_polygon: { "type" => "Polygon" })
      expect(cluster).not_to be_mapped
    end
  end

  describe "validations" do
    it "requires name" do
      cluster = build(:cluster, name: nil)
      expect(cluster).not_to be_valid
    end

    it "requires unique name" do
      create(:cluster, name: "Unique Sector")
      duplicate = build(:cluster, name: "Unique Sector")
      expect(duplicate).not_to be_valid
    end

    it "requires region" do
      cluster = build(:cluster, region: nil)
      expect(cluster).not_to be_valid
    end
  end

  # =========================================================================
  # POSTGIS SPATIAL QUERIES
  # =========================================================================
  describe "PostGIS spatial queries" do
    let(:polygon) do
      {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
    end

    describe "#contains_point?" do
      it "returns true for a point inside the polygon" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.contains_point?(49.45, 31.95)).to be true
      end

      it "returns false for a point outside the polygon" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.contains_point?(0, 0)).to be false
      end

      it "returns false when geo_boundary is absent" do
        cluster = create(:cluster, geojson_polygon: nil)
        expect(cluster.contains_point?(49.45, 31.95)).to be false
      end
    end

    describe ".containing_point" do
      it "returns clusters that contain the given point" do
        cluster = create(:cluster, geojson_polygon: polygon)
        _other = create(:cluster, geojson_polygon: nil)

        result = described_class.containing_point(49.45, 31.95)
        expect(result).to include(cluster)
      end

      it "returns empty when no cluster contains the point" do
        create(:cluster, geojson_polygon: polygon)
        expect(described_class.containing_point(0, 0)).to be_empty
      end
    end

    describe "geo_boundary trigger sync" do
      it "auto-populates geo_boundary when geojson_polygon is set" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.geo_boundary_present?).to be true
      end

      it "sets geo_boundary to NULL when geojson_polygon is nil" do
        cluster = create(:cluster, geojson_polygon: nil)
        expect(cluster.geo_boundary_present?).to be false
      end
    end
  end
end

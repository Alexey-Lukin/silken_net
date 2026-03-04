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
end

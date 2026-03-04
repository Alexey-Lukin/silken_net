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
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe GatewayBlueprint, type: :model do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, :geolocated, cluster: cluster) }

  describe "default view" do
    subject(:parsed) { JSON.parse(described_class.render(gateway)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(gateway.id)
    end

    it "includes uid and state" do
      expect(parsed["uid"]).to eq(gateway.uid)
      expect(parsed["state"]).to be_present
    end

    it "includes location fields" do
      expect(parsed["latitude"]).to be_present
      expect(parsed["longitude"]).to be_present
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "does not expose sensitive fields like ip_address or config" do
      expect(parsed).not_to have_key("ip_address")
      expect(parsed).not_to have_key("config_sleep_interval_s")
      expect(parsed).not_to have_key("latest_voltage_mv")
    end
  end

  describe "collection rendering" do
    let!(:gateways) { create_list(:gateway, 3, cluster: cluster) }

    it "renders an array of gateways" do
      parsed = JSON.parse(described_class.render(gateways))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed).to all(include("uid", "state"))
    end
  end
end

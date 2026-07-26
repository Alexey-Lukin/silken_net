# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::LogEntry do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  def mock_gateway(uid: "SNET-Q-AABB0011", ip_address: "192.168.1.100")
    OpenStruct.new(uid: uid, ip_address: ip_address)
  end

  describe "rendering" do
    let(:html) { render_component(gateway: mock_gateway, hex_payload: "DEADBEEF1234", timestamp: Time.new(2024, 6, 15, 10, 30, 45)) }

    it "renders the gateway UID" do
      expect(html).to include("SNET-Q-AABB0011")
    end

    it "displays the IP address" do
      expect(html).to include("192.168.1.100")
    end

    it "displays the hex payload" do
      expect(html).to include("DEADBEEF1234")
    end

    it "renders BATCH_RECEIVED status" do
      expect(html).to include("BATCH_RECEIVED")
    end

    it "renders the timestamp with milliseconds" do
      expect(html).to include("10:30:45")
    end

    it "renders as a table row" do
      expect(html).to include("<tr")
    end

    it "applies hover effect" do
      expect(html).to include("hover:bg-gaia-surface-sunken")
    end

    it "applies slide-in animation" do
      expect(html).to include("slide-in-from-left")
    end
  end

  describe "nil gateway handling" do
    let(:html) { render_component(gateway: nil, hex_payload: "AABB", timestamp: Time.current) }

    it "shows UNKNOWN_RELAY for nil gateway" do
      expect(html).to include("UNKNOWN_RELAY")
    end

    it "shows ?.?.?.? for nil IP" do
      expect(html).to include("?.?.?.?")
    end
  end

  describe "various hex payloads" do
    it "renders short payload" do
      html = render_component(gateway: mock_gateway, hex_payload: "FF", timestamp: Time.current)
      expect(html).to include("FF")
    end

    it "renders long payload" do
      long_payload = "A" * 64
      html = render_component(gateway: mock_gateway, hex_payload: long_payload, timestamp: Time.current)
      expect(html).to include(long_payload)
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(gateway: mock_gateway, hex_payload: "BEEF", timestamp: Time.current) }

    it "uses text-mini for timestamp" do
      expect(html).to include("text-mini")
    end

    it "uses text-micro for IP label and status" do
      expect(html).to include("text-micro")
    end

    it "uses font-mono for data display" do
      expect(html).to include("font-mono")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-gaia-primary")
    end

    it "uses tracking-widest for status text" do
      expect(html).to include("tracking-widest")
    end
  end
end

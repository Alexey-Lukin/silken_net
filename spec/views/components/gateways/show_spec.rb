# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateways::Show do
  let(:gateway) { mock_gateway }
  let(:latest_log) { mock_latest_log }
  let(:active_soldiers) { [ mock_soldier ] }
  let(:html) { render_component(gateway: gateway, latest_log: latest_log, active_soldiers: active_soldiers) }

  def mock_gateway(uid: "SNET-Q-AAB01234", state: "active", ip_address: "192.168.1.42",
                   last_seen_at: 1.minute.ago, cluster_name: "Carpathian-Alpha",
                   sleep_interval: 120, firmware_version: "2.1.0",
                   firmware_hash: "a1b2c3d4e5f67890abcdef1234567890", hardware_key_uid: "HK-001")
    cluster = OpenStruct.new(name: cluster_name)
    hardware_key = OpenStruct.new(device_uid: hardware_key_uid)

    gw = OpenStruct.new(
      uid: uid,
      state: state,
      ip_address: ip_address,
      last_seen_at: last_seen_at,
      cluster: cluster,
      config_sleep_interval_s: sleep_interval,
      firmware_version: firmware_version,
      firmware_hash: firmware_hash,
      hardware_key: hardware_key
    )
    gw.define_singleton_method(:model_name) { ActiveModel::Name.new(Gateway) }
    gw.define_singleton_method(:to_key) { [ 1 ] }
    gw.define_singleton_method(:to_param) { "1" }
    gw
  end

  def mock_latest_log(signal_quality_percentage: 85, cellular_signal_csq: 18,
                      voltage_mv: 4100, temperature_c: 23)
    OpenStruct.new(
      signal_quality_percentage: signal_quality_percentage,
      cellular_signal_csq: cellular_signal_csq,
      voltage_mv: voltage_mv,
      temperature_c: temperature_c
    )
  end

  def mock_soldier(did: "SNET-00000001", active: true, under_threat: false)
    soldier = OpenStruct.new(did: did)
    soldier.define_singleton_method(:active?) { active }
    soldier.define_singleton_method(:under_threat?) { under_threat }
    soldier
  end

  describe "argument validation" do
    it "raises ArgumentError if gateway does not respond to :uid" do
      expect {
        component_class.new(gateway: Object.new, latest_log: nil, active_soldiers: [])
      }.to raise_error(ArgumentError, /uid/)
    end
  end

  describe "status header" do
    it "displays Queen Relay // UID" do
      expect(html).to include("Queen Relay // SNET-Q-AAB01234")
    end

    it "displays the IP address" do
      expect(html).to include("192.168.1.42")
    end

    it "shows 0.0.0.0 when IP is nil" do
      gw = mock_gateway(ip_address: nil)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("0.0.0.0")
    end

    it "shows heartbeat timestamp" do
      frozen_time = Time.zone.parse("2025-03-15 14:30:00")
      gw = mock_gateway(last_seen_at: frozen_time)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("14:30:00 // 15.03.25")
    end

    it "shows SILENT when last_seen_at is nil" do
      gw = mock_gateway(last_seen_at: nil)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("SILENT")
    end
  end

  describe "state badge" do
    it "renders active state with emerald style" do
      expect(html).to include("active")
      expect(html).to include("border-emerald-500")
      expect(html).to include("text-emerald-500")
    end

    it "renders updating state with warning style" do
      gw = mock_gateway(state: "updating")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("updating")
      expect(rendered).to include("border-status-warning")
    end

    it "renders maintenance state with blue style" do
      gw = mock_gateway(state: "maintenance")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("maintenance")
      expect(rendered).to include("border-blue-500")
    end

    it "renders faulty state with red style" do
      gw = mock_gateway(state: "faulty")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("faulty")
      expect(rendered).to include("border-red-500")
    end
  end

  describe "technical matrix" do
    it "displays signal strength percentage" do
      expect(html).to include("Signal Strength")
      expect(html).to include("85%")
    end

    it "displays CSQ value" do
      expect(html).to include("CSQ: 18")
    end

    it "displays voltage in mV" do
      expect(html).to include("Voltage Matrix")
      expect(html).to include("4100")
    end

    it "displays temperature in °C" do
      expect(html).to include("Thermal State")
      expect(html).to include("23°C")
    end

    it "falls back to 0 when latest_log is nil" do
      rendered = render_component(gateway: gateway, latest_log: nil, active_soldiers: active_soldiers)
      expect(rendered).to include("0%")
      expect(rendered).to include("CSQ: 0")
    end
  end

  describe "battery color" do
    it "shows red border when voltage is below 3400mV" do
      log = mock_latest_log(voltage_mv: 3200)
      rendered = render_component(gateway: gateway, latest_log: log, active_soldiers: active_soldiers)
      expect(rendered).to include("border-red-900")
    end

    it "shows emerald border when voltage is healthy" do
      log = mock_latest_log(voltage_mv: 4100)
      rendered = render_component(gateway: gateway, latest_log: log, active_soldiers: active_soldiers)
      expect(rendered).not_to include("border-red-900")
    end
  end

  describe "soldier fleet overview" do
    it "displays active soldiers count" do
      expect(html).to include("1 Active nodes")
    end

    it "renders soldier node indicator with DID" do
      expect(html).to include("SNET-00000001")
    end

    it "renders emerald indicator for active soldier" do
      expect(html).to include("border-emerald-500")
    end

    it "renders gray indicator for inactive soldier" do
      soldiers = [ mock_soldier(did: "SNET-INACTIVE", active: false) ]
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: soldiers)
      expect(rendered).to include("border-gray-800")
    end

    it "renders red pulsing indicator for under-threat soldier" do
      soldiers = [ mock_soldier(did: "SNET-THREAT", active: true, under_threat: true) ]
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: soldiers)
      expect(rendered).to include("border-red-600")
      expect(rendered).to include("animate-pulse")
    end

    it "handles empty soldier list" do
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: [])
      expect(rendered).to include("0 Active nodes")
    end
  end

  describe "network config" do
    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "shows UNASSIGNED when cluster is nil" do
      gw = mock_gateway(cluster_name: nil)
      gw.cluster = nil
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("UNASSIGNED")
    end

    it "displays sleep interval" do
      expect(html).to include("120s")
    end

    it "displays firmware version" do
      expect(html).to include("2.1.0")
    end

    it "displays truncated firmware hash" do
      expect(html).to include("a1b2c3d4e5f67890")
    end
  end

  describe "hardware vault" do
    it "displays hardware key UID" do
      expect(html).to include("HK-001")
    end

    it "shows UNDEFINED when hardware key is nil" do
      gw = mock_gateway(hardware_key_uid: nil)
      gw.hardware_key = nil
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("UNDEFINED")
    end
  end

  describe "connection LED" do
    it "shows green LED when recently seen" do
      gw = mock_gateway(last_seen_at: 1.minute.ago)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("bg-emerald-500")
    end

    it "shows red pulsing LED when not recently seen" do
      gw = mock_gateway(last_seen_at: 10.minutes.ago)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
    end
  end
end

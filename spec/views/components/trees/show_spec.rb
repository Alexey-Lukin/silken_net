# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Show do
  # Component is i18n-aware. Assertions reference English copy, so render
  # under :en. UA fallback is exercised in the `default locale` describe-block.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  let(:tree) { mock_tree }
  let(:latest_log) { mock_latest_log }
  let(:recent_logs) { [ mock_recent_log ] }
  let(:maintenance_history) { [ mock_maintenance_record ] }
  let(:html) do
    render_component(tree: tree, latest_log: latest_log,
                     recent_logs: recent_logs, maintenance_history: maintenance_history)
  end

  def mock_tree(did: "SNET-00000042", status: "active", current_stress: 0.35,
                family_name: "Quercus Robur", baseline_impedance: 100.0,
                device_uid: "HK-SOLDIER-042", scc_balance: 12.5,
                crypto_address: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
                wallet_balance: 42.0, cluster_name: "Carpathian-Alpha",
                latitude: 49.4444, longitude: 32.0597,
                ionic_voltage: 3800, last_seen_at: 1.minute.ago,
                under_threat: false)
    family = OpenStruct.new(name: family_name, baseline_impedance: baseline_impedance)
    hardware_key = device_uid ? OpenStruct.new(device_uid: device_uid) : nil
    wallet = OpenStruct.new(
      scc_balance: scc_balance,
      crypto_public_address: crypto_address,
      balance: wallet_balance
    )
    cluster = OpenStruct.new(name: cluster_name)

    t = OpenStruct.new(
      did: did,
      status: status,
      current_stress: current_stress,
      tree_family: family,
      hardware_key: hardware_key,
      wallet: wallet,
      cluster: cluster,
      latitude: latitude,
      longitude: longitude,
      ionic_voltage: ionic_voltage,
      last_seen_at: last_seen_at
    )
    t.define_singleton_method(:under_threat?) { under_threat }
    t.define_singleton_method(:active?) { status == "active" }
    t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
    t.define_singleton_method(:to_key) { [ 1 ] }
    t.define_singleton_method(:to_param) { "1" }
    t
  end

  def mock_latest_log(z_value: 28.7, voltage_mv: 3800, temperature_c: 22, created_at: 5.minutes.ago)
    OpenStruct.new(
      z_value: z_value,
      voltage_mv: voltage_mv,
      temperature_c: temperature_c,
      created_at: created_at
    )
  end

  def mock_recent_log(z_value: 27.5, created_at: 10.minutes.ago)
    OpenStruct.new(z_value: z_value, created_at: created_at)
  end

  def mock_maintenance_record(technician: "Ivan Koval", action_type: "sensor_replacement",
                              notes: "Replaced corroded electrode on north-facing anchor point",
                              performed_at: 2.days.ago)
    user = OpenStruct.new(full_name: technician)
    OpenStruct.new(user: user, action_type: action_type, notes: notes, performed_at: performed_at)
  end

  describe "argument validation" do
    it "raises ArgumentError if tree does not respond to :did" do
      expect {
        component_class.new(tree: Object.new, latest_log: nil,
                            recent_logs: [], maintenance_history: [])
      }.to raise_error(ArgumentError, /did/)
    end
  end

  describe "header" do
    it "displays tree DID" do
      expect(html).to include("SNET-00000042")
    end

    it "displays the tree status" do
      expect(html).to include("active")
    end

    it "displays family name" do
      expect(html).to include("Quercus Robur")
    end

    it "displays uplink timestamp from latest_log" do
      frozen_time = Time.zone.parse("2025-06-10 14:30:00")
      log = mock_latest_log(created_at: frozen_time)
      rendered = render_component(tree: tree, latest_log: log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("14:30:00 // 10.06.25")
    end

    it "shows SILENT when no latest_log" do
      rendered = render_component(tree: tree, latest_log: nil,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("SILENT")
    end
  end

  describe "status badge colors" do
    it "renders active with the gaia primary token" do
      expect(html).to include("border-gaia-primary")
      expect(html).to include("text-gaia-primary")
    end

    it "renders dormant with warning style" do
      t = mock_tree(status: "dormant")
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("border-status-warning")
    end

    it "renders deceased with red style" do
      t = mock_tree(status: "deceased")
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("border-red-800")
      expect(rendered).to include("text-red-800")
    end
  end

  describe "family name" do
    it "displays 'Unknown' when family is nil" do
      t = mock_tree(family_name: nil)
      t.tree_family = OpenStruct.new(name: nil, baseline_impedance: 100.0)
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("Unknown")
    end
  end

  describe "biometric panel" do
    it "displays z_value from latest_log" do
      expect(html).to include("28.7")
    end

    it "displays --- when no latest_log z_value" do
      rendered = render_component(tree: tree, latest_log: nil,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("---")
    end

    it "displays voltage" do
      expect(html).to include("3800")
      expect(html).to include("mV")
    end

    it "displays temperature" do
      expect(html).to include("22")
      expect(html).to include("°C")
    end

    it "displays stress index percentage" do
      expect(html).to include("35.0%")
    end

    it "renders the impedance label" do
      expect(html).to include("Impedance")
    end
  end

  describe "radial SVG" do
    it "renders SVG element" do
      expect(html).to include("<svg")
    end

    it "calculates correct stroke-dashoffset" do
      # offset = 552 * (1 - 0.35) = 552 * 0.65 = 358.8
      expect(html).to include("stroke-dashoffset: 358.8")
    end

    it "uses emerald stroke when not under threat" do
      expect(html).to include("stroke-emerald-500")
    end

    it "uses red pulse stroke when under threat" do
      t = mock_tree(under_threat: true)
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("stroke-red-600")
      expect(rendered).to include("animate-pulse")
    end
  end

  describe "impedance history" do
    it "renders impedance flux section" do
      expect(html).to include("Impedance Flux")
    end

    it "renders bars for recent logs" do
      logs = [ mock_recent_log(z_value: 50.0), mock_recent_log(z_value: 75.0) ]
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: logs, maintenance_history: maintenance_history)
      expect(rendered).to include("50.0")
      expect(rendered).to include("75.0")
    end
  end

  describe "maintenance ledger" do
    it "displays table headers" do
      expect(html).to include("Technician")
      expect(html).to include("Action")
      expect(html).to include("Observations")
      expect(html).to include("Timestamp")
    end

    it "displays technician name" do
      expect(html).to include("Ivan Koval")
    end

    it "displays action type" do
      expect(html).to include("sensor_replacement")
    end

    it "truncates long notes to 50 characters" do
      long_notes = "A" * 100
      record = mock_maintenance_record(notes: long_notes)
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: [ record ])
      expect(rendered).to include("A" * 47 + "...")
    end

    it "shows empty state when no maintenance records" do
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: [])
      expect(rendered).to include("No physical interventions recorded")
    end
  end

  describe "economic panel" do
    it "displays wallet balance" do
      expect(html).to include("12.5")
    end

    it "displays SCC label" do
      expect(html).to include("SCC")
    end

    it "truncates crypto address" do
      expect(html).to include("0xABCDEF1234...")
    end

    it "shows NOT_PROVISIONED when no wallet address" do
      t = mock_tree(crypto_address: nil)
      t.wallet.crypto_public_address = nil
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("NOT_PROVISIONED")
    end
  end

  describe "hardware security vault" do
    it "displays device_uid" do
      expect(html).to include("HK-SOLDIER-042")
    end

    it "shows NOT_PROVISIONED when hardware key is nil" do
      t = mock_tree(device_uid: nil)
      t.hardware_key = nil
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("NOT_PROVISIONED")
    end

    it "displays cipher suite info" do
      # Post-ARCH.42 (2026-05-23): Tree LoRa channel — AES-128-ECB (locale label).
      expect(html).to include("AES-128-ECB")
    end

    it "renders rotate key button with aria-label" do
      expect(html).to include("Rotate Hardware Key")
      expect(html).to include("aria-label")
    end
  end

  describe "metadata panel" do
    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays coordinates" do
      expect(html).to include("49.4444")
      expect(html).to include("32.0597")
    end

    it "includes Google Maps link" do
      expect(html).to include("google.com/maps")
      expect(html).to include("49.4444")
    end

    it "includes focus-visible accessibility ring" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "chronicle turbo frame" do
    it "renders a lazy-loaded turbo frame" do
      expect(html).to include("tree_chronicle")
      expect(html).to include('loading="lazy"')
    end
  end

  describe "edge cases — nil-safe rendering of optional fields" do
    it "renders 'Unknown' technician when maintenance record has no user" do
      record = OpenStruct.new(user: nil, action_type: "calibration",
                              notes: "Quick recalibration", performed_at: 1.day.ago)
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: [ record ])
      expect(rendered).to include("Unknown")
    end

    it "renders '—' when maintenance notes are nil" do
      record = OpenStruct.new(user: OpenStruct.new(full_name: "Olha"), action_type: "inspection",
                              notes: nil, performed_at: 1.day.ago)
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: [ record ])
      expect(rendered).to include("—")
    end

    it "renders '—' when maintenance performed_at is nil" do
      record = OpenStruct.new(user: OpenStruct.new(full_name: "Olha"), action_type: "inspection",
                              notes: "Sane", performed_at: nil)
      rendered = render_component(tree: tree, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: [ record ])
      expect(rendered).to include("—")
    end

    it "renders '0.0' SCC when tree has no wallet" do
      t = mock_tree
      t.wallet = nil
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      expect(rendered).to include("0.0")
      expect(rendered).to include("NOT_PROVISIONED")
    end

    it "renders without a cluster when tree.cluster is nil" do
      t = mock_tree
      t.cluster = nil
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      # Should still render the metadata panel without crashing
      expect(rendered).to include("Deployment")
    end

    it "skips impedance bars when family has no positive baseline_impedance" do
      t = mock_tree(baseline_impedance: nil)
      rendered = render_component(tree: t, latest_log: latest_log,
                                  recent_logs: recent_logs, maintenance_history: maintenance_history)
      # Header still renders; bars simply absent — no crash
      expect(rendered).to include("Impedance Flux")
    end
  end
end

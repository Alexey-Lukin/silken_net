# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertDispatchService, type: :service do
  let(:family) { create(:tree_family) }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: family) }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow(SilkenNet::Attractor).to receive(:homeostatic?).and_return(true)
  end

  describe "vandalism vs low-voltage logic" do
    it "returns early (skips fire analysis) when tamper is detected" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_tamper_detected?: true,
        voltage_mv: 50
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("vandalism_breach")
      expect(alert.message).to include("Втручання в корпус")
    end

    it "continues fire analysis when voltage is low but no tamper" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_tamper_detected?: false,
        voltage_mv: 50,
        temperature_c: 80,
        bio_status_anomaly?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(2)

      alert_types = EwsAlert.last(2).map(&:alert_type)
      expect(alert_types).to include("system_fault")
      expect(alert_types).to include("fire_detected")
    end

    it "does not trigger fire when voltage is low but temperature is normal" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_tamper_detected?: false,
        voltage_mv: 50,
        temperature_c: 25,
        bio_status_anomaly?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("system_fault")
    end
  end

  describe "cache invalidation on critical alerts" do
    it "clears oracle yield cache when a critical alert is created" do
      Rails.cache.write("oracle_expected_yield_24h", 42.0)

      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_tamper_detected?: true,
        voltage_mv: 50
      )

      described_class.analyze_and_trigger!(log)

      expect(Rails.cache.read("oracle_expected_yield_24h")).to be_nil
    end

    it "does not clear oracle yield cache for non-critical alerts" do
      Rails.cache.write("oracle_expected_yield_24h", 42.0)

      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_tamper_detected?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        bio_status_stress?: true,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      expect(Rails.cache.read("oracle_expected_yield_24h")).to eq(42.0)
    end
  end
end

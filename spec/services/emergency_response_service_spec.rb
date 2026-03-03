# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmergencyResponseService do
  before do
    allow(ActuatorCommandWorker).to receive(:perform_async)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, latitude: 49.4285, longitude: 32.0620) }
  let(:gateway) { create(:gateway, :online, :geolocated, cluster: cluster) }

  describe ".call" do
    context "with severe_drought alert" do
      let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

      it "splits 7200s duration into two 3600s commands per actuator" do
        valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: valve, ews_alert: alert)
        expect(commands.count).to eq(2)
        expect(commands.pluck(:duration_seconds)).to all(eq(3600))
        expect(commands.pluck(:command_payload)).to all(eq("OPEN_VALVE"))
      end
    end

    context "with fire_detected alert" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

      it "splits 14400s duration into four 3600s valve commands" do
        valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: valve, ews_alert: alert)
        expect(commands.count).to eq(4)
        expect(commands.pluck(:duration_seconds)).to all(eq(3600))
      end

      it "creates a single 3600s siren command" do
        siren = create(:actuator, :fire_siren, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: siren, ews_alert: alert)
        expect(commands.count).to eq(1)
        expect(commands.first.duration_seconds).to eq(3600)
        expect(commands.first.command_payload).to eq("ACTIVATE_SIREN")
      end
    end

    context "with insect_epidemic alert" do
      let(:alert) { create(:ews_alert, cluster: cluster, tree: tree, alert_type: :insect_epidemic, severity: :low) }

      it "creates a single 3600s command (no splitting needed)" do
        valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: valve, ews_alert: alert)
        expect(commands.count).to eq(1)
        expect(commands.first.duration_seconds).to eq(3600)
      end
    end

    context "with seismic_anomaly alert" do
      let(:alert) { create(:ews_alert, cluster: cluster, tree: tree, alert_type: :seismic_anomaly, severity: :critical) }

      it "creates a single 1800s beacon command (no splitting needed)" do
        beacon = create(:actuator, :seismic_beacon, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: beacon, ews_alert: alert)
        expect(commands.count).to eq(1)
        expect(commands.first.duration_seconds).to eq(1800)
        expect(commands.first.command_payload).to eq("ACTIVATE_BEACON")
      end
    end
  end

  describe "bulk insert (N+1 fix)" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "creates commands for multiple actuators in a single insert" do
      3.times { create(:actuator, :water_valve, gateway: gateway, state: :idle) }

      # 3 actuators × 2 chunks (7200/3600) = 6 commands total
      expect { described_class.call(alert) }
        .to change(ActuatorCommand, :count).by(6)
    end

    it "enqueues a worker for each created command" do
      2.times { create(:actuator, :water_valve, gateway: gateway, state: :idle) }

      described_class.call(alert)

      # 2 actuators × 2 chunks = 4 worker calls
      expect(ActuatorCommandWorker).to have_received(:perform_async).exactly(4).times
    end
  end

  describe "gateway proximity prioritization" do
    let(:alert) { create(:ews_alert, cluster: cluster, tree: tree, alert_type: :insect_epidemic, severity: :low) }

    it "orders actuators by gateway proximity to the alert tree" do
      near_gw = create(:gateway, :online, cluster: cluster, latitude: 49.4286, longitude: 32.0621)
      far_gw  = create(:gateway, :online, cluster: cluster, latitude: 50.0000, longitude: 33.0000)

      far_actuator  = create(:actuator, :water_valve, gateway: far_gw, state: :idle)
      near_actuator = create(:actuator, :water_valve, gateway: near_gw, state: :idle)

      described_class.call(alert)

      commands = ActuatorCommand.where(ews_alert: alert).order(:id)
      actuator_ids = commands.pluck(:actuator_id)

      expect(actuator_ids).to eq([ near_actuator.id, far_actuator.id ])
    end
  end

  describe ".duration_chunks" do
    it "returns single chunk for duration <= 3600" do
      expect(described_class.send(:duration_chunks, 3600)).to eq([ 3600 ])
      expect(described_class.send(:duration_chunks, 1800)).to eq([ 1800 ])
    end

    it "splits 7200 into two 3600 chunks" do
      expect(described_class.send(:duration_chunks, 7200)).to eq([ 3600, 3600 ])
    end

    it "splits 14400 into four 3600 chunks" do
      expect(described_class.send(:duration_chunks, 14400)).to eq([ 3600, 3600, 3600, 3600 ])
    end

    it "handles remainders correctly" do
      expect(described_class.send(:duration_chunks, 5400)).to eq([ 3600, 1800 ])
    end
  end
end

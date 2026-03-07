# frozen_string_literal: true

require "rails_helper"

RSpec.describe GatewayTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster) }

  let(:valid_stats) do
    {
      "voltage_mv" => 4200,
      "temperature_c" => 25.0,
      "cellular_signal_csq" => 15,
      "ip_address" => "10.0.0.42"
    }
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "creates a GatewayTelemetryLog record" do
      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to change(GatewayTelemetryLog, :count).by(1)

      log = GatewayTelemetryLog.last
      expect(log.voltage_mv).to eq(4200)
      expect(log.temperature_c).to eq(25.0)
      expect(log.cellular_signal_csq).to eq(15)
    end

    it "updates gateway last_seen_at and IP" do
      freeze_time do
        described_class.new.perform(gateway.uid, valid_stats)

        gateway.reload
        expect(gateway.ip_address).to eq("10.0.0.42")
        expect(gateway.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    context "with critical telemetry" do
      it "creates EwsAlert for low battery" do
        stats = valid_stats.merge("voltage_mv" => 3000)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        expect(alert.message).to include("виснажена")
      end

      it "creates EwsAlert for overheating" do
        stats = valid_stats.merge("temperature_c" => 70.0)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        expect(EwsAlert.last.message).to include("перегріта")
      end

      it "creates EwsAlert for weak signal" do
        stats = valid_stats.merge("cellular_signal_csq" => 2)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        expect(EwsAlert.last.message).to include("Слабкий сигнал")
      end

      it "enqueues AlertNotificationWorker for critical faults" do
        stats = valid_stats.merge("voltage_mv" => 3000)

        described_class.new.perform(gateway.uid, stats)

        # Одне з EwsAlert callback, друге з check_system_health
        expect(AlertNotificationWorker.jobs.size).to be >= 1
      end
    end

    context "with valid CSQ=99 (unknown signal)" do
      it "accepts the stats without creating alert" do
        stats = valid_stats.merge("cellular_signal_csq" => 99)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(GatewayTelemetryLog, :count).by(1)
      end
    end

    context "with invalid stats" do
      it "rejects stats with nil voltage" do
        stats = valid_stats.merge("voltage_mv" => nil)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects stats with nil temperature" do
        stats = valid_stats.merge("temperature_c" => nil)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects stats with nil signal" do
        stats = valid_stats.merge("cellular_signal_csq" => nil)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end
    end

    it "handles unknown gateway UID gracefully" do
      expect(Rails.logger).to receive(:error).with(/фантомний шлюз/)

      expect {
        described_class.new.perform("SNET-Q-FFFFFFFF", valid_stats)
      }.not_to raise_error
    end

    it "re-raises StandardError for Sidekiq retry" do
      allow_any_instance_of(Gateway).to receive(:mark_seen!).and_raise(StandardError, "DB lock timeout")

      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to raise_error(StandardError, "DB lock timeout")
    end

    it "does not create alert when gateway has no cluster" do
      gateway_no_cluster = create(:gateway, cluster: nil)
      stats = valid_stats.merge("voltage_mv" => 3000)

      expect {
        described_class.new.perform(gateway_no_cluster.uid, stats)
      }.not_to change(EwsAlert, :count)
    end
  end
end

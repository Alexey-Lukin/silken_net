# frozen_string_literal: true

require "rails_helper"

# [ARCH.54 Шар 1] Споживач пульсу Королеви: stats приходить з ПІДПИСАНОГО
# health-блоку QATT-v2 (UnpackTelemetryWorker#enqueue_envelope_health) —
# стара DID=0-милиця з voltage/temp вбита; напруги/температури v2 не несе
# (Королева без ADC — колонки лишаються nil до заліза).
RSpec.describe GatewayTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster) }

  let(:valid_stats) do
    {
      "uptime_min" => 5310,
      "cifo_fill" => 12,
      "lora_rx_drops" => 0,
      "coap_fail_count" => 0,
      "cellular_signal_csq" => 15,
      "flags" => 0,
      "ip_address" => "10.0.0.42"
    }
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "creates a GatewayTelemetryLog pulse record" do
      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to change(GatewayTelemetryLog, :count).by(1)

      log = GatewayTelemetryLog.last
      expect(log.uptime_min).to eq(5310)
      expect(log.cifo_fill).to eq(12)
      expect(log.lora_rx_drops).to eq(0)
      expect(log.coap_fail_count).to eq(0)
      expect(log.cellular_signal_csq).to eq(15)
      expect(log.health_flags).to eq(0)
      # v2-пульс напруги не несе — чесний nil, не фальшивий нуль
      expect(log.voltage_mv).to be_nil
      expect(log.temperature_c).to be_nil
    end

    it "updates gateway last_seen_at and IP (без voltage — нема ADC)" do
      freeze_time do
        described_class.new.perform(gateway.uid, valid_stats)

        gateway.reload
        expect(gateway.ip_address).to eq("10.0.0.42")
        expect(gateway.last_seen_at).to be_within(1.second).of(Time.current)
        expect(gateway.latest_voltage_mv).to be_nil
      end
    end

    it "accepts nil csq (модем не відповів — сентинель 0xFF на дроті)" do
      stats = valid_stats.merge("cellular_signal_csq" => nil)

      expect {
        described_class.new.perform(gateway.uid, stats)
      }.to change(GatewayTelemetryLog, :count).by(1)

      expect(GatewayTelemetryLog.last.cellular_signal_csq).to be_nil
    end

    context "with critical pulse" do
      it "creates EwsAlert for weak signal" do
        stats = valid_stats.merge("cellular_signal_csq" => 2)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        expect(alert.message).to include("Слабкий сигнал")
      end

      it "creates EwsAlert for degraded uplink (coap_fail_count ≥ поріг)" do
        stats = valid_stats.merge("coap_fail_count" => 12)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        expect(EwsAlert.last.message).to include("провалених")
      end

      it "не плодить дублікат при активному system_fault кластера (анти-спам)" do
        stats = valid_stats.merge("cellular_signal_csq" => 2)
        described_class.new.perform(gateway.uid, stats)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(EwsAlert, :count)
      end

      it "no_signal (csq 99) не тригерить алерт (за специфікацією 3GPP)" do
        stats = valid_stats.merge("cellular_signal_csq" => 99)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(EwsAlert, :count)
      end
    end

    context "with invalid stats (KENOSIS-гейт)" do
      it "rejects pulse without uptime_min" do
        stats = valid_stats.except("uptime_min")

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects pulse without cifo_fill" do
        stats = valid_stats.except("cifo_fill")

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects out-of-range csq (не 0-31/99)" do
        stats = valid_stats.merge("cellular_signal_csq" => 42)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end
    end

    it "logs error for phantom gateway without raising" do
      expect {
        described_class.new.perform("SNET-Q-DEADBEEF", valid_stats)
      }.not_to change(GatewayTelemetryLog, :count)
    end
  end
end

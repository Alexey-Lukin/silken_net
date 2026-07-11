# frozen_string_literal: true

require "rails_helper"

# [FW.56] Money-path front-door: CoapGate.handle_datagram МУСИТЬ поставити батч
# у чергу ПЕРЕД поверненням reply (яким демон шле ACK 2.04). Інакше Королева
# почистить CIFO [FW.51] на батч, який Redis не прийняв → тиха втрата телеметрії.
# Раніше інваріант тримався лише порядком рядків демона (редаговано PERF.1 без guard).
RSpec.describe CoapGate do
  let(:gateway_ip) { "10.0.0.7" }
  let(:reply_bytes) { "\x60\x44".b }

  before do
    allow($stdout).to receive(:puts)
    allow(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL).to receive(:increment)
  end

  def result(status:, payload: nil, reply: nil, gateway_uid: nil)
    double("CoapResult", status: status, payload: payload, reply: reply, gateway_uid: gateway_uid)
  end

  context "when telemetry_batch — enqueue ПЕРЕД ACK" do
    before do
      allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
        .and_return(result(status: :telemetry_batch, payload: "batch",
                           reply: reply_bytes, gateway_uid: "SNET-Q-AABBCCDD"))
    end

    it "ставить у чергу і повертає reply для ACK" do
      expect(UnpackTelemetryWorker).to receive(:perform_async)
      expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
    end

    it "НЕ повертає reply, якщо enqueue впав (демон не шле ACK) + метрика enqueue_error" do
      allow(UnpackTelemetryWorker).to receive(:perform_async).and_raise(StandardError, "redis down")
      expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
        .to receive(:increment).with(labels: { status: "enqueue_error" })
      expect { described_class.handle_datagram(data: "small", gateway_ip: gateway_ip) }
        .to raise_error(StandardError, "redis down")
    end
  end

  it "oversized → nil (мовчазний дроп, без парсингу/черги, FW.51)" do
    expect(CoapServerPdu).not_to receive(:handle_telemetry_datagram)
    expect(UnpackTelemetryWorker).not_to receive(:perform_async)
    expect(described_class.handle_datagram(data: "x" * described_class::MAX_PACKET_SIZE, gateway_ip: gateway_ip)).to be_nil
  end

  it "unknown_route → reply без черги" do
    allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
      .and_return(result(status: :unknown_route, reply: reply_bytes))
    expect(UnpackTelemetryWorker).not_to receive(:perform_async)
    expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
  end

  it "malformed → reply без черги" do
    allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
      .and_return(result(status: :malformed, reply: reply_bytes))
    expect(UnpackTelemetryWorker).not_to receive(:perform_async)
    expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
  end
end

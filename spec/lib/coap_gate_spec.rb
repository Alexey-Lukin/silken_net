# SPDX-License-Identifier: AGPL-3.0-or-later
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
    instance_double(CoapServerPdu::Intake, status: status, payload: payload, reply: reply, gateway_uid: gateway_uid)
  end

  context "when telemetry_batch — enqueue ПЕРЕД ACK" do
    before do
      allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
        .and_return(result(status: :telemetry_batch, payload: "batch",
                           reply: reply_bytes, gateway_uid: "SNET-Q-AABBCCDD"))
    end

    it "ставить у чергу і повертає reply для ACK" do
      allow(UnpackTelemetryWorker).to receive(:perform_async)

      expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
      expect(UnpackTelemetryWorker).to have_received(:perform_async)
    end

    it "НЕ повертає reply, якщо enqueue впав (демон не шле ACK) + метрика enqueue_error" do
      allow(UnpackTelemetryWorker).to receive(:perform_async).and_raise(StandardError, "redis down")

      expect { described_class.handle_datagram(data: "small", gateway_ip: gateway_ip) }
        .to raise_error(StandardError, "redis down")

      expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
        .to have_received(:increment).with(labels: { status: "enqueue_error" })
    end
  end

  it "oversized → nil (мовчазний дроп, без парсингу/черги, FW.51)" do
    allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
    allow(UnpackTelemetryWorker).to receive(:perform_async)

    expect(described_class.handle_datagram(data: "x" * described_class::MAX_PACKET_SIZE, gateway_ip: gateway_ip)).to be_nil
    expect(CoapServerPdu).not_to have_received(:handle_telemetry_datagram)
    expect(UnpackTelemetryWorker).not_to have_received(:perform_async)
  end

  it "unknown_route → reply без черги" do
    allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
      .and_return(result(status: :unknown_route, reply: reply_bytes))
    allow(UnpackTelemetryWorker).to receive(:perform_async)

    expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
    expect(UnpackTelemetryWorker).not_to have_received(:perform_async)
  end

  it "malformed → reply без черги" do
    allow(CoapServerPdu).to receive(:handle_telemetry_datagram)
      .and_return(result(status: :malformed, reply: reply_bytes))
    allow(UnpackTelemetryWorker).to receive(:perform_async)

    expect(described_class.handle_datagram(data: "small", gateway_ip: gateway_ip)).to eq(reply_bytes)
    expect(UnpackTelemetryWorker).not_to have_received(:perform_async)
  end

  # [FW.60] Queen-pull гілки: poll + ota chunk-server
  describe "downlink poll (FW.60)" do
    let(:request) do
      instance_double(CoapServerPdu::Request, type: CoapServerPdu::TYPE_CON, message_id: 7)
    end

    def poll_result(uid: "SNET-Q-00000001", req: request, query: {})
      result(status: :downlink_poll, gateway_uid: uid).tap do |r|
        allow(r).to receive_messages(request: req, query: query)
      end
    end

    before { CoapGate::REPLY_CACHE.clear }

    it "derive'ить чергу і відповідає 2.05 з конвертом" do
      gateway = create(:gateway)
      allow(Downlink::PendingQueueService).to receive(:poll_reply)
        .with(gateway: gateway, query: {}).and_return("ENVELOPE".b)
      allow(CoapServerPdu).to receive_messages(handle_telemetry_datagram: poll_result(uid: gateway.uid), build_content: "REPLY205".b)

      expect(described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)).to eq("REPLY205".b)
    end

    it "невідомий uid → 4.04, derivation не торкається" do
      allow(CoapServerPdu).to receive_messages(handle_telemetry_datagram: poll_result(uid: "SNET-Q-DEADBEEF"), build_ack: "ACK404".b)
      allow(Downlink::PendingQueueService).to receive(:poll_reply)

      expect(described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)).to eq("ACK404".b)
      expect(Downlink::PendingQueueService).not_to have_received(:poll_reply)
    end

    it "NON-poll → мовчазний дроп (контракт = CON)" do
      non_request = instance_double(CoapServerPdu::Request, type: CoapServerPdu::TYPE_NON)
      allow(CoapServerPdu).to receive(:handle_telemetry_datagram).and_return(poll_result(req: non_request))

      expect(described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)).to be_nil
    end

    it "CON-ретрансміт (той самий MID) → закешована відповідь без re-derivation" do
      gateway = create(:gateway)
      allow(Downlink::PendingQueueService).to receive(:poll_reply).once.and_return("ENVELOPE".b)
      allow(CoapServerPdu).to receive_messages(handle_telemetry_datagram: poll_result(uid: gateway.uid), build_content: "REPLY205".b)

      first  = described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)
      replay = described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)

      expect(replay).to eq(first)
      expect(Downlink::PendingQueueService).to have_received(:poll_reply).once
    end

    it "порожня derivation (нема KEYC) → 4.04" do
      gateway = create(:gateway)
      allow(Downlink::PendingQueueService).to receive(:poll_reply).and_return(nil)
      allow(CoapServerPdu).to receive_messages(handle_telemetry_datagram: poll_result(uid: gateway.uid), build_ack: "ACK404".b)

      expect(described_class.handle_datagram(data: "x", gateway_ip: gateway_ip)).to eq("ACK404".b)
    end
  end
end

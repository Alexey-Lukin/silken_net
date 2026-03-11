# frozen_string_literal: true

require "rails_helper"
require "coap_client"

RSpec.describe CoapClient do
  let(:mock_socket) { instance_double(UDPSocket) }

  before do
    allow(UDPSocket).to receive(:new).and_return(mock_socket)
    allow(mock_socket).to receive(:send)
    allow(mock_socket).to receive(:close)
  end

  describe ".put" do
    context "when gateway responds with success (2.xx)" do
      it "returns a Response with success? = true" do
        # Build a valid CoAP 2.05 Content response
        # Version 1, Type 2 (ACK), TKL 0 → first byte = 0x60
        # Code = 2.05 → class 2 (0b010), detail 05 (0b00101) → 0x45
        message_id = 1
        response_packet = [ 0x60, 0x45, message_id ].pack("CCn") + "\xFF".b + "OK".b

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])

        # We need to control the random message_id
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        result = described_class.put("coap://192.168.1.1:5683/telemetry/batch/QUEEN1", "test_payload")

        expect(result.success?).to be true
        expect(result.payload).to eq("OK")
      end
    end

    context "when gateway does not respond (timeout)" do
      it "raises NetworkError" do
        allow(IO).to receive(:select).and_return(nil)

        expect {
          described_class.put("coap://192.168.1.1/telemetry", "test", timeout: 1)
        }.to raise_error(CoapClient::NetworkError, /не відповів/)
      end
    end

    context "when gateway returns client error (4.xx)" do
      it "raises ClientError" do
        message_id = 1
        # Code 4.04 (Not Found): class 4 = 0b100, detail 04 = 0b00100 → 0x84
        response_packet = [ 0x60, 0x84, message_id ].pack("CCn")

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        expect {
          described_class.put("coap://192.168.1.1/telemetry", "test")
        }.to raise_error(CoapClient::ClientError)
      end
    end

    context "when gateway returns server error (5.xx)" do
      it "raises ServerError" do
        message_id = 1
        # Code 5.00 (Internal Server Error): class 5 = 0b101, detail 00 → 0xA0
        response_packet = [ 0x60, 0xA0, message_id ].pack("CCn")

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        expect {
          described_class.put("coap://192.168.1.1/telemetry", "test")
        }.to raise_error(CoapClient::ServerError)
      end
    end

    context "when message ID does not match" do
      it "raises NetworkError" do
        message_id = 1
        wrong_message_id = 2
        response_packet = [ 0x60, 0x45, wrong_message_id ].pack("CCn")

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        expect {
          described_class.put("coap://192.168.1.1/telemetry", "test")
        }.to raise_error(CoapClient::NetworkError, /MID mismatch/)
      end
    end

    context "when URL has query parameters" do
      it "encodes URI query options in the packet" do
        message_id = 1
        response_packet = [ 0x60, 0x45, message_id ].pack("CCn") + "\xFF".b + "OK".b

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        result = described_class.put("coap://192.168.1.1/telemetry?key=value", "test")
        expect(result.success?).to be true
      end
    end

    context "when response has unknown class code" do
      it "returns a Response with success? = false" do
        message_id = 1
        # Code class 3 (unknown), detail 0 → 0x60
        response_packet = [ 0x60, 0x60, message_id ].pack("CCn")

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        result = described_class.put("coap://192.168.1.1/telemetry", "test")
        expect(result.success?).to be false
      end
    end

    it "always closes the socket" do
      allow(IO).to receive(:select).and_return(nil)

      expect {
        described_class.put("coap://192.168.1.1/telemetry", "test", timeout: 1)
      }.to raise_error(CoapClient::NetworkError)

      expect(mock_socket).to have_received(:close)
    end
  end
end

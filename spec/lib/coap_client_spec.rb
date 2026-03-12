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

    context "when option delta is >= 13 (extended delta)" do
      it "handles large delta options in encoding" do
        message_id = 1
        response_packet = [ 0x60, 0x45, message_id ].pack("CCn") + "\xFF".b + "OK".b

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        # Large option delta >= 13 is triggered with specific URI path patterns
        # Since Uri-Path is option 11, it won't trigger delta >= 13 on its own.
        # Uri-Query is option 15 - delta from 11 to 15 is only 4.
        # We can test encode_option directly:
        buffer = described_class.send(:encode_option, 14, "v")
        expect(buffer.bytesize).to be > 2

        result = described_class.put("coap://192.168.1.1/telemetry?key=value", "test")
        expect(result.success?).to be true
      end
    end

    context "when value length >= 13 (extended length)" do
      it "handles long option values" do
        message_id = 1
        response_packet = [ 0x60, 0x45, message_id ].pack("CCn") + "\xFF".b + "OK".b

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        # Build a URL with a long path segment (>= 13 bytes) to exercise extended length encoding
        long_segment = "a" * 20
        result = described_class.put("coap://192.168.1.1/#{long_segment}", "test")
        expect(result.success?).to be true
      end
    end

    context "when response payload marker is absent" do
      it "returns nil payload" do
        message_id = 1
        # A response with no 0xFF marker (no payload)
        response_packet = [ 0x60, 0x45, message_id ].pack("CCn")

        allow(IO).to receive(:select).and_return([ [ mock_socket ] ])
        allow(mock_socket).to receive(:recvfrom).and_return([ response_packet, nil ])
        allow_any_instance_of(Object).to receive(:rand).with(1..65535).and_return(message_id)

        result = described_class.put("coap://192.168.1.1/telemetry", "test")
        expect(result.success?).to be true
        expect(result.payload).to be_nil
      end
    end
  end

  describe ".parse_response" do
    it "returns success Response for a valid 2.xx code" do
      message_id = 42
      data = [ 0x60, 0x45, message_id ].pack("CCn") + "\xFF".b + "test".b
      result = described_class.send(:parse_response, data, message_id)
      expect(result.success?).to be true
      expect(result.payload).to eq("test")
    end
  end

  describe "socket management and parsing" do
    it "closes socket even when an error occurs" do
      mock_socket = instance_double(UDPSocket)
      allow(UDPSocket).to receive(:new).and_return(mock_socket)
      allow(mock_socket).to receive(:send)
      allow(mock_socket).to receive(:close)
      allow(IO).to receive(:select).and_return(nil)

      expect {
        CoapClient.put("coap://192.168.1.1:5683/test", "payload", timeout: 1)
      }.to raise_error(CoapClient::NetworkError)

      expect(mock_socket).to have_received(:close)
    end

    it "handles unknown class code (not 2, 4, or 5) in parse_response" do
      # Class code 0 is neither 2 (success), 4 (client error), nor 5 (server error)
      # This falls through to the else branch in the case statement
      header = [ 0x00, 0x00, 0x04D2 ].pack("CCn") # version=0, code=0 (class=0, detail=0), MID=1234
      response = CoapClient.send(:parse_response, header, 1234)
      expect(response).not_to be_nil
      expect(response.success?).to be false
      expect(response.class_string).to eq("0.00")
    end

    it "handles class code 1 (informational, not 2/4/5) in parse_response" do
      # Class code 1 is neither 2 (success), 4 (client error), nor 5 (server error)
      # code = (1 << 5) | 0 = 32, class=1, detail=0
      code = (1 << 5) | 0
      header = [ 0x60, code, 0x04D2 ].pack("CCn") # ACK type, code=1.00, MID=1234
      response = CoapClient.send(:parse_response, header, 1234)
      expect(response).not_to be_nil
      expect(response.success?).to be false
      expect(response.class_string).to eq("1.00")
    end
  end
end

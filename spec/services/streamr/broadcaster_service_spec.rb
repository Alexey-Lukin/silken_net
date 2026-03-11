# frozen_string_literal: true

require "rails_helper"

RSpec.describe Streamr::BroadcasterService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"b" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }
  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#broadcast!" do
    context "when Streamr credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(streamr_stream_id: "0xabc123/silken-net/telemetry", streamr_api_key: "test-streamr-key-456")
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it "publishes telemetry to Streamr successfully" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_http).to receive(:request).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.broadcast!

        expect(result).to be_a(Net::HTTPSuccess)
      end

      it "sends correct payload structure to Streamr" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        allow(mock_http).to receive(:request) do |request|
          body = JSON.parse(request.body)
          expect(body["tree_id"]).to eq(tree.id)
          expect(body["peaq_did"]).to eq(tree.peaq_did)
          expect(body["lorenz_state"]).to include("z_value", "bio_status")
          expect(body["timestamp"]).to be_present
          expect(body["alerts"]).to include("critical", "acoustic_events", "temperature_c", "voltage_mv")
          response
        end

        described_class.new(telemetry_log).broadcast!
      end

      it "URL-encodes the stream_id in the request URI" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        allow(mock_http).to receive(:request) do |request|
          expect(request.path).to include("0xabc123%2Fsilken-net%2Ftelemetry")
          response
        end

        described_class.new(telemetry_log).broadcast!
      end

      it "raises BroadcastError when Streamr returns error" do
        error_response = Net::HTTPInternalServerError.allocate
        allow(error_response).to receive_messages(code: "500", body: "Internal Server Error")
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_http).to receive(:request).and_return(error_response)

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Streamr повернув 500/)
      end

      it "raises BroadcastError on network failure" do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Збій зв'язку з Streamr/)
      end

      it "raises BroadcastError on timeout" do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Збій зв'язку з Streamr/)
      end
    end

    context "when streamr_stream_id is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(streamr_stream_id: nil, streamr_api_key: "test-key")
      end

      it "raises BroadcastError" do
        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /streamr_stream_id не налаштовано/)
      end
    end

    context "when streamr_api_key is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(streamr_stream_id: "0xabc123/test", streamr_api_key: nil)
      end

      it "raises BroadcastError" do
        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /streamr_api_key не налаштовано/)
      end
    end
  end
end

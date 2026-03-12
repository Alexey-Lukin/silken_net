# frozen_string_literal: true

require "rails_helper"

RSpec.describe Streamr::BroadcasterService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"b" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#broadcast!" do
    context "when Streamr credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(streamr_stream_id: "0xabc123/silken-net/telemetry", streamr_api_key: "test-streamr-key-456")
      end

      it "publishes telemetry to Streamr successfully" do
        response = Web3::HttpClient::Response.new("{}".to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.broadcast!

        expect(result).to be_a(Web3::HttpClient::Response)
      end

      it "sends correct payload structure to Streamr" do
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          body = kwargs[:body]
          expect(body[:tree_id]).to eq(tree.id)
          expect(body[:peaq_did]).to eq(tree.peaq_did)
          expect(body[:lorenz_state]).to include(:z_value, :bio_status)
          expect(body[:timestamp]).to be_present
          expect(body[:alerts]).to include(:critical, :acoustic_events, :temperature_c, :voltage_mv)
          Web3::HttpClient::Response.new("{}".to_json)
        end

        described_class.new(telemetry_log).broadcast!
      end

      it "URL-encodes the stream_id in the request URL" do
        allow(Web3::HttpClient).to receive(:post) do |url, **_kwargs|
          expect(url).to include("0xabc123%2Fsilken-net%2Ftelemetry")
          Web3::HttpClient::Response.new("{}".to_json)
        end

        described_class.new(telemetry_log).broadcast!
      end

      it "raises BroadcastError when Streamr returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Streamr API returned 500: Internal Server Error"))

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Streamr API returned 500/)
      end

      it "raises BroadcastError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Streamr connection error: Connection refused"))

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Streamr connection error/)
      end

      it "raises BroadcastError on timeout" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Streamr Timeout: execution expired"))

        service = described_class.new(telemetry_log)

        expect {
          service.broadcast!
        }.to raise_error(Streamr::BroadcasterService::BroadcastError, /Streamr Timeout/)
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

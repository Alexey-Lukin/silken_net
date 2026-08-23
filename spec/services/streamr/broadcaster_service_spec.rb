# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Streamr::BroadcasterService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"b" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    silence_broadcasts!(:tree_map)
    # SEC.22: creds resolve ENV-primary; neutralize ambient .env (dotenv) so these
    # specs deterministically exercise the credentials path regardless of a local .env.
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STREAMR_STREAM_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("STREAMR_API_KEY").and_return(nil)
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

    context "when both ENV and credentials are set (SEC.22 — ENV wins)" do
      before do
        allow(ENV).to receive(:[]).with("STREAMR_STREAM_ID").and_return("env-stream/telemetry")
        allow(ENV).to receive(:[]).with("STREAMR_API_KEY").and_return("env-key")
        allow(Rails.application.credentials).to receive_messages(streamr_stream_id: "cred-stream", streamr_api_key: "cred-key")
      end

      it "uses the ENV values, not the credentials values" do
        allow(Web3::HttpClient).to receive(:post) do |url, **kwargs|
          expect(url).to include("env-stream%2Ftelemetry")
          expect(kwargs[:headers]["Authorization"]).to eq("Bearer env-key")
          Web3::HttpClient::Response.new("{}".to_json)
        end

        described_class.new(telemetry_log).broadcast!
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

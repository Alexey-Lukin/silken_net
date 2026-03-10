# frozen_string_literal: true

require "rails_helper"

RSpec.describe Iotex::W3bstreamVerificationService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }
  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#verify!" do
    context "when W3bstream credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: "https://w3bstream.example.com", iotex_api_key: "test-api-key-123")
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it "returns a zk_proof_ref on successful verification" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:body).and_return({ proof_id: "zk-proof-abc123" }.to_json)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_http).to receive(:request).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.verify!

        expect(result).to eq("zk-proof-abc123")
      end

      it "accepts receipt_id as alternative proof reference" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:body).and_return({ receipt_id: "receipt-xyz789" }.to_json)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_http).to receive(:request).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.verify!

        expect(result).to eq("receipt-xyz789")
      end

      it "sends correct payload to W3bstream" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:body).and_return({ proof_id: "zk-proof-abc123" }.to_json)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        allow(mock_http).to receive(:request) do |request|
          body = JSON.parse(request.body)
          expect(body["device_id"]).to eq(tree.did)
          expect(body["peaq_did"]).to eq(tree.peaq_did)
          expect(body["telemetry_log_id"]).to eq(telemetry_log.id_value)
          expect(body["chaotic_data"]["z_value"]).to be_a(Float)
          expect(body["hardware_signature"]).to be_present
          response
        end

        described_class.new(telemetry_log).verify!
      end

      it "raises VerificationError when W3bstream returns error" do
        error_response = Net::HTTPInternalServerError.allocate
        allow(error_response).to receive_messages(code: "500", body: "Internal Server Error")
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_http).to receive(:request).and_return(error_response)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /W3bstream повернув 500/)
      end

      it "raises VerificationError when response has no proof reference" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:body).and_return({}.to_json)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_http).to receive(:request).and_return(response)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /не повернув proof reference/)
      end

      it "raises VerificationError on invalid JSON response" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:body).and_return("not json")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_http).to receive(:request).and_return(response)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /Невалідна JSON-відповідь/)
      end

      it "raises VerificationError on network failure" do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /Збій зв'язку з W3bstream/)
      end
    end

    context "when iotex_w3bstream_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: nil, iotex_api_key: "test-api-key")
      end

      it "raises VerificationError" do
        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /iotex_w3bstream_url не налаштовано/)
      end
    end

    context "when iotex_api_key is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: "https://w3bstream.example.com", iotex_api_key: nil)
      end

      it "raises VerificationError" do
        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /iotex_api_key не налаштовано/)
      end
    end
  end
end

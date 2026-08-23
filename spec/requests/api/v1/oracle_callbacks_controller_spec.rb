# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OracleCallbacksController, type: :request do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) do
    create(:telemetry_log,
      tree: tree,
      verified_by_iotex: true,
      zk_proof_ref: "zk-proof-abc123",
      chainlink_request_id: "chainlink-req-test123",
      oracle_status: "dispatched"
    )
  end

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "POST /oracle_callbacks" do
    context "when successful callback" do
      it "updates oracle_status to fulfilled and enqueues MintCarbonCoinWorker and SolanaMicroRewardWorker" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("fulfilled")

        telemetry_log.reload
        expect(telemetry_log.oracle_status).to eq("fulfilled")

        # EVM (Polygon) мінтинг
        expect(MintCarbonCoinWorker.jobs.size).to eq(1)
        expect(MintCarbonCoinWorker.jobs.first["args"].first).to eq(telemetry_log.id_value)

        # Solana мікро-винагорода (паралельно)
        expect(SolanaMicroRewardWorker.jobs.size).to eq(1)
        expect(SolanaMicroRewardWorker.jobs.first["args"].first).to eq(telemetry_log.id_value)
      end

      it "uses created_at for partition-pruned lookup when provided" do
        post "/api/v1/oracle_callbacks",
             params: {
               chainlink_request_id: telemetry_log.chainlink_request_id,
               created_at: telemetry_log.created_at.iso8601(6),
               success: true
             },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("fulfilled")
      end
    end

    context "when failed callback" do
      it "updates oracle_status to failed and does not enqueue minting" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: false, error: "Oracle timeout" },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("failed")
        expect(response.parsed_body["error"]).to eq("Oracle timeout")

        telemetry_log.reload
        expect(telemetry_log.oracle_status).to eq("failed")

        expect(MintCarbonCoinWorker.jobs.size).to eq(0)
        expect(SolanaMicroRewardWorker.jobs.size).to eq(0)
      end

      it "uses default error message when error param is missing" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: false },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["error"]).to eq("Unknown oracle error")
      end
    end

    context "when chainlink_request_id not found" do
      it "returns 404" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: "nonexistent-req-id", success: true },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when created_at is malformed" do
      it "ignores the malformed created_at and still finds the log" do
        post "/api/v1/oracle_callbacks",
             params: {
               chainlink_request_id: telemetry_log.chainlink_request_id,
               created_at: "not-a-valid-date",
               success: true
             },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("fulfilled")
      end
    end

    it "does not require authentication" do
      post "/api/v1/oracle_callbacks",
           params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
           as: :json

      expect(response).to have_http_status(:ok)
    end

    context "with HMAC signature validation" do
      let(:hmac_secret) { "test-chainlink-hmac-secret-256bit" }

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CHAINLINK_HMAC_SECRET").and_return(hmac_secret)
      end

      it "accepts valid HMAC signature" do
        body = { chainlink_request_id: telemetry_log.chainlink_request_id, success: true }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, body)

        post "/api/v1/oracle_callbacks",
             params: body,
             headers: { "Content-Type" => "application/json", "X-Chainlink-Signature" => signature }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("fulfilled")
      end

      it "rejects missing HMAC signature" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("Missing X-Chainlink-Signature")
      end

      it "rejects invalid HMAC signature" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             headers: { "X-Chainlink-Signature" => "invalid-signature-hex" },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("Invalid HMAC")
      end
    end

    context "with WEB3_STRICT_MODE=true and missing CHAINLINK_HMAC_SECRET (SEC.5)" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CHAINLINK_HMAC_SECRET").and_return(nil)
        allow(ENV).to receive(:[]).with("WEB3_STRICT_MODE").and_return("true")
      end

      it "raises SecurityError to prevent unprotected oracle callbacks" do
        expect {
          post "/api/v1/oracle_callbacks",
               params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
               as: :json
        }.to raise_error(SecurityError, /CHAINLINK_HMAC_SECRET обов'язковий/)
      end
    end

    context "with replay attack prevention (A-6)" do
      it "returns 409 Conflict when callback is replayed for already fulfilled log" do
        # First callback — succeeds
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json
        expect(response).to have_http_status(:ok)

        # Second callback — replay attack blocked
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json
        expect(response).to have_http_status(:conflict)
      end

      it "returns 409 Conflict when callback is replayed for already failed log" do
        # First callback — fails
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: false },
             as: :json
        expect(response).to have_http_status(:ok)

        # Replay attempt
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json
        expect(response).to have_http_status(:conflict)
      end

      it "does not enqueue minting workers on replay" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json

        # Verify first callback enqueued workers
        expect(MintCarbonCoinWorker.jobs.size).to eq(1)
        expect(SolanaMicroRewardWorker.jobs.size).to eq(1)

        MintCarbonCoinWorker.jobs.clear
        SolanaMicroRewardWorker.jobs.clear

        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json

        expect(MintCarbonCoinWorker.jobs.size).to eq(0)
        expect(SolanaMicroRewardWorker.jobs.size).to eq(0)
      end
    end
  end
end

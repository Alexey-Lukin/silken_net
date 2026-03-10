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
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "POST /api/v1/oracle_callbacks" do
    context "when successful callback" do
      it "updates oracle_status to fulfilled and enqueues MintCarbonCoinWorker" do
        post "/api/v1/oracle_callbacks",
             params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("fulfilled")

        telemetry_log.reload
        expect(telemetry_log.oracle_status).to eq("fulfilled")

        expect(MintCarbonCoinWorker.jobs.size).to eq(1)
        expect(MintCarbonCoinWorker.jobs.first["args"]).to eq([ telemetry_log.id_value ])
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

    it "does not require authentication" do
      post "/api/v1/oracle_callbacks",
           params: { chainlink_request_id: telemetry_log.chainlink_request_id, success: true },
           as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end

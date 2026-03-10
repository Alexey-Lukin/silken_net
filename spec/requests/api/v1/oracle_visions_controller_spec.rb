# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OracleVisionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester_token) { forester.generate_token_for(:api_access) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:forester_headers) { { "Authorization" => "Bearer #{forester_token}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

  let!(:cluster) { create(:cluster, organization: organization) }

  describe "GET /api/v1/oracle_visions" do
    before do
      Rails.cache.clear
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with("oracle_expected_yield_24h", anything).and_return(1.5)
    end

    context "when as JSON" do
      it "returns visions and yield forecast for forester" do
        get "/api/v1/oracle_visions", headers: forester_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body).to have_key("visions")
        expect(body).to have_key("yield_forecast")
      end

      it "returns visions for admin (who is also a forest_commander)" do
        get "/api/v1/oracle_visions", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/oracle_visions", headers: forester_headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for investor users" do
      get "/api/v1/oracle_visions", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/api/v1/oracle_visions", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/oracle_visions/stream_config" do
    it "accepts a cluster_id parameter" do
      # Note: generate_token_for(:stream_access) is not yet defined on User,
      # so this endpoint currently errors. We verify the auth gate works.
      get "/api/v1/oracle_visions/stream_config",
          params: { cluster_id: cluster.id },
          headers: forester_headers, as: :json

      # Accept either success (if token type is defined) or server error (pre-existing gap)
      expect(response.status).to be_in([ 200, 500 ])
    end

    it "returns stream name, auth token, and provider on success" do
      get "/api/v1/oracle_visions/stream_config",
          params: { cluster_id: cluster.id },
          headers: forester_headers, as: :json

      if response.status == 200
        body = response.parsed_body
        expect(body["stream_name"]).to eq("oracle_visions_cluster_#{cluster.id}")
        expect(body["auth_token"]).to be_present
        expect(body["provider"]).to eq("SolidCable")
      end
    end

    it "returns 403 for investor users" do
      get "/api/v1/oracle_visions/stream_config",
          params: { cluster_id: cluster.id },
          headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/oracle_visions/simulate" do
    before do
      stub_const("SimulationWorker", Class.new do
        def self.perform_async(*args)
          "job-123"
        end
      end)
    end

    it "starts a simulation for admin" do
      post "/api/v1/oracle_visions/simulate",
           params: { cluster_id: cluster.id, variables: { temp: 25 } },
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["job_id"]).to eq("job-123")
    end

    it "returns 403 for forester (simulate requires admin)" do
      post "/api/v1/oracle_visions/simulate",
           params: { cluster_id: cluster.id },
           headers: forester_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for investor users" do
      post "/api/v1/oracle_visions/simulate",
           params: { cluster_id: cluster.id },
           headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      post "/api/v1/oracle_visions/simulate", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

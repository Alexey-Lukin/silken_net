# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::DashboardController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:cluster) { create(:cluster, organization: organization) }

  describe "GET /api/v1/dashboard" do
    context "when as JSON" do
      it "returns dashboard stats" do
        get "/api/v1/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body).to have_key("trees")
        expect(body).to have_key("economy")
        expect(body).to have_key("security")
        expect(body).to have_key("energy")
      end

      it "returns correct tree stats" do
        tree = create(:tree, cluster: cluster, status: :active)
        create(:telemetry_log, tree: tree, voltage_mv: 4200, created_at: 30.minutes.ago)

        get "/api/v1/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        trees = response.parsed_body["trees"]
        expect(trees["total"]).to be >= 1
        expect(trees["active"]).to be >= 1
      end

      it "returns economy stats with wallet balance" do
        tree = create(:tree, cluster: cluster)
        create(:wallet, tree: tree, balance: 100.0)

        get "/api/v1/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        economy = response.parsed_body["economy"]
        expect(economy["total_scc"]).to be_a(Numeric)
      end

      it "returns security stats" do
        tree = create(:tree, cluster: cluster)
        create(:ews_alert, cluster: cluster, tree: tree, status: :active)

        get "/api/v1/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        security = response.parsed_body["security"]
        expect(security["active_alerts"]).to be >= 1
      end

      it "returns energy stats" do
        get "/api/v1/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        energy = response.parsed_body["energy"]
        expect(energy).to have_key("avg_voltage")
        expect(energy).to have_key("status")
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/dashboard", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/dashboard", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "energy status branches" do
      it "returns LOW_RESERVE when no telemetry data exists" do
        get "/api/v1/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        energy = response.parsed_body["energy"]
        expect(energy["avg_voltage"]).to eq(0)
        expect(energy["status"]).to eq("LOW_RESERVE")
      end

      it "returns STABLE when average voltage exceeds 3300 mV" do
        tree = create(:tree, cluster: cluster, status: :active)
        create(:telemetry_log, tree: tree, voltage_mv: 4200, created_at: 10.minutes.ago)
        create(:telemetry_log, tree: tree, voltage_mv: 4000, created_at: 20.minutes.ago)

        get "/api/v1/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        energy = response.parsed_body["energy"]
        expect(energy["avg_voltage"]).to be > 3300
        expect(energy["status"]).to eq("STABLE")
      end
    end
  end
end

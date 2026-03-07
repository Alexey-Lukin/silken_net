# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TelemetryController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  describe "GET /api/v1/telemetry/live" do
    context "as HTML" do
      it "renders the live telemetry dashboard" do
        get "/api/v1/telemetry/live", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/telemetry/live"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/trees/:id/telemetry (tree_history)" do
    let(:tree_family) { create(:tree_family) }
    let(:own_tree) { create(:tree, cluster: own_cluster, tree_family: tree_family) }
    let(:other_tree) { create(:tree, cluster: other_cluster, tree_family: tree_family) }

    before do
      create(:telemetry_log, tree: own_tree, z_value: 0.35, temperature_c: 22.5, created_at: 1.day.ago)
      create(:telemetry_log, tree: own_tree, z_value: 0.40, temperature_c: 23.0, created_at: 2.hours.ago)
    end

    it "returns telemetry history for a tree in the user's organization" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { tree_id: own_tree.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["did"]).to eq(own_tree.did)
      expect(body["unit"]).to eq("kOhm")
      expect(body["timestamps"]).to be_an(Array)
      expect(body["impedance"]).to be_an(Array)
      expect(body["temperature"]).to be_an(Array)
      expect(body["stress_index"]).to be_an(Array)
      expect(body["timestamps"].length).to eq(2)
    end

    it "supports days parameter" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { tree_id: own_tree.id, days: 1 },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a tree from another organization" do
      get "/api/v1/trees/#{other_tree.id}/telemetry",
          params: { tree_id: other_tree.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      get "/api/v1/trees/#{own_tree.id}/telemetry", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gateways/:id/telemetry (gateway_history)" do
    let(:own_gateway) { create(:gateway, cluster: own_cluster) }
    let(:other_gateway) { create(:gateway, cluster: other_cluster) }

    before do
      create(:gateway_telemetry_log, gateway: own_gateway, voltage_mv: 4200,
             cellular_signal_csq: 15, temperature_c: 25.0, created_at: 1.day.ago)
      create(:gateway_telemetry_log, gateway: own_gateway, voltage_mv: 4100,
             cellular_signal_csq: 14, temperature_c: 24.0, created_at: 2.hours.ago)
    end

    it "returns telemetry history for a gateway in the user's organization" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry",
          params: { gateway_id: own_gateway.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["uid"]).to eq(own_gateway.uid)
      expect(body["timestamps"]).to be_an(Array)
      expect(body["voltage"]).to be_an(Array)
      expect(body["signal"]).to be_an(Array)
      expect(body["temp"]).to be_an(Array)
      expect(body["timestamps"].length).to eq(2)
    end

    it "supports days parameter" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry",
          params: { gateway_id: own_gateway.id, days: 1 },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a gateway from another organization" do
      get "/api/v1/gateways/#{other_gateway.id}/telemetry",
          params: { gateway_id: other_gateway.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

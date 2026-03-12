# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TreesController, type: :request do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_tree) { create(:tree, cluster: own_cluster) }
  let!(:other_tree) { create(:tree, cluster: other_cluster) }

  describe "GET /api/v1/clusters/:cluster_id/trees" do
    it "returns trees from a cluster in the user's organization" do
      get "/api/v1/clusters/#{own_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["trees"].map { |t| t["id"] }
      expect(ids).to include(own_tree.id)
    end

    it "returns pagination metadata" do
      get "/api/v1/clusters/#{own_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
    end

    it "returns 404 for a cluster from another organization" do
      get "/api/v1/clusters/#{other_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/trees/:id" do
    it "returns a tree belonging to the user's organization" do
      get "/api/v1/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tree"]["id"]).to eq(own_tree.id)
    end

    it "includes telemetry data with null values when no logs exist" do
      get "/api/v1/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      telemetry = response.parsed_body["telemetry"]
      expect(telemetry["z_value"]).to eq(0)
      expect(telemetry["temperature"]).to be_nil
      expect(telemetry["voltage"]).to be_nil
      expect(telemetry["last_sync"]).to be_nil
    end

    it "includes telemetry data when logs exist" do
      create(:telemetry_log, tree: own_tree,
        z_value: 1.5, temperature_c: 25.0, voltage_mv: 3500)

      get "/api/v1/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      telemetry = response.parsed_body["telemetry"]
      expect(telemetry["z_value"].to_f).to eq(1.5)
      expect(telemetry["temperature"].to_f).to eq(25.0)
      expect(telemetry["voltage"].to_i).to eq(3500)
      expect(telemetry["last_sync"]).to be_present
    end

    it "returns 404 for a tree from another organization" do
      get "/api/v1/trees/#{other_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/clusters/#{own_cluster.id}/trees", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/trees/#{own_tree.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

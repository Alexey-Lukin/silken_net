# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ActuatorsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, :forester, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:own_gateway) { create(:gateway, :online, cluster: own_cluster) }
  let(:other_gateway) { create(:gateway, :online, cluster: other_cluster) }
  let!(:own_actuator) { create(:actuator, gateway: own_gateway) }
  let!(:other_actuator) { create(:actuator, gateway: other_gateway) }

  describe "GET /api/v1/clusters/:cluster_id/actuators" do
    it "returns actuators for the user's organization cluster" do
      get "/api/v1/clusters/#{own_cluster.id}/actuators", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_actuator.id)
    end

    it "returns 404 for a cluster from another organization" do
      get "/api/v1/clusters/#{other_cluster.id}/actuators", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/actuators/:id" do
    it "returns an actuator belonging to the user's organization" do
      get "/api/v1/actuators/#{own_actuator.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["actuator"]["id"]).to eq(own_actuator.id)
    end

    it "returns 404 for an actuator from another organization" do
      get "/api/v1/actuators/#{other_actuator.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end

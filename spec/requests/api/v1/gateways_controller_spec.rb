# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::GatewaysController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_gateway) { create(:gateway, cluster: own_cluster) }
  let!(:other_gateway) { create(:gateway, cluster: other_cluster) }

  describe "GET /api/v1/gateways" do
    it "returns only gateways belonging to the user's organization" do
      get "/api/v1/gateways", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body.map { |g| g["id"] }
      expect(ids).to include(own_gateway.id)
      expect(ids).not_to include(other_gateway.id)
    end
  end

  describe "GET /api/v1/gateways/:id" do
    it "returns a gateway belonging to the user's organization" do
      get "/api/v1/gateways/#{own_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_gateway.id)
    end

    it "returns 404 for a gateway from another organization" do
      get "/api/v1/gateways/#{other_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end

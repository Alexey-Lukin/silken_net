# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ClustersController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  describe "GET /api/v1/clusters" do
    it "returns only clusters belonging to the user's organization" do
      get "/api/v1/clusters", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(own_cluster.id)
      expect(ids).not_to include(other_cluster.id)
    end
  end

  describe "GET /api/v1/clusters/:id" do
    it "returns a cluster belonging to the user's organization" do
      get "/api/v1/clusters/#{own_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_cluster.id)
    end

    it "returns 404 for a cluster from another organization" do
      get "/api/v1/clusters/#{other_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/clusters", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/clusters/#{own_cluster.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

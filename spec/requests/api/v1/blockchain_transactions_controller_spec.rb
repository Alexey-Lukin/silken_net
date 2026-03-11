# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BlockchainTransactionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:own_tree) { create(:tree, cluster: own_cluster) }
  let(:other_tree) { create(:tree, cluster: other_cluster) }
  let(:own_wallet) { create(:wallet, tree: own_tree) }
  let(:other_wallet) { create(:wallet, tree: other_tree) }

  let!(:own_tx) { create(:blockchain_transaction, wallet: own_wallet) }
  let!(:other_tx) { create(:blockchain_transaction, wallet: other_wallet) }

  describe "GET /api/v1/blockchain_transactions" do
    it "returns only transactions belonging to the user's organization" do
      get "/api/v1/blockchain_transactions", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |t| t["id"] }
      expect(ids).to include(own_tx.id)
      expect(ids).not_to include(other_tx.id)
    end
  end

  describe "GET /api/v1/blockchain_transactions/:id" do
    it "returns a transaction belonging to the user's organization" do
      get "/api/v1/blockchain_transactions/#{own_tx.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_tx.id)
    end

    it "returns 404 for a transaction from another organization" do
      get "/api/v1/blockchain_transactions/#{other_tx.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/blockchain_transactions", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/blockchain_transactions/#{own_tx.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

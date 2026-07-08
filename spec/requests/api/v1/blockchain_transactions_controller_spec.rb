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

    it "filters by token_type (carbon_coin)" do
      get "/api/v1/blockchain_transactions",
          params: { token_type: "carbon_coin" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "filters by status (pending)" do
      get "/api/v1/blockchain_transactions",
          params: { status: "pending" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    # =========================================================================
    # ENUM WHITELIST: status/token_type are integer-backed AR enums; passing
    # an unrecognised string used to surface as PG::InvalidTextRepresentation
    # (HTTP 500). Both branches now respond 400 with an i18n message.
    # =========================================================================
    it "rejects bogus token_type with 400" do
      get "/api/v1/blockchain_transactions",
          params: { token_type: "SCC" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("SCC")
    end

    it "rejects bogus status with 400" do
      get "/api/v1/blockchain_transactions",
          params: { status: "garbled" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("garbled")
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

    # =========================================================================
    # PARTITION PRUNING: passing `created_at` scopes the query to a single
    # partition instead of scanning all of them (see `find_transaction`).
    # =========================================================================
    it "finds the transaction when a matching created_at is supplied (partition pruning)" do
      # `find_transaction` matches `created_at` by EXACT equality — round-trip
      # with microsecond precision (iso8601(6)) or the default (whole-second)
      # `iso8601` truncates the stored sub-second timestamp and matches nothing.
      get "/api/v1/blockchain_transactions/#{own_tx.id}",
          params: { created_at: own_tx.created_at.iso8601(6) }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_tx.id)
    end

    it "falls back to a full scan when created_at is not valid ISO 8601" do
      get "/api/v1/blockchain_transactions/#{own_tx.id}",
          params: { created_at: "not-a-date" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_tx.id)
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

  describe "GET /api/v1/blockchain_transactions/:id/on_chain" do
    it "renders on-chain verification Turbo Frame" do
      get "/api/v1/blockchain_transactions/#{own_tx.id}/on_chain", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end
end

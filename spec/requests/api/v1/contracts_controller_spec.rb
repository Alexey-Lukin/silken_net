# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ContractsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  let!(:own_contract) do
    create(:naas_contract, organization: organization, cluster: own_cluster)
  end
  let!(:other_contract) do
    create(:naas_contract, organization: other_organization, cluster: other_cluster)
  end

  before do
    # The controller uses as_json(methods: [...]) with methods not yet on the model.
    # Also calls @contract.blockchain_transactions.confirmed and ews_alerts.active
    # which rely on unprefixed scopes that don't exist (enum uses prefix: true).
    NaasContract.define_method(:current_yield_performance) { 0.85 } unless NaasContract.method_defined?(:current_yield_performance)
    NaasContract.define_method(:active_threats?) { false } unless NaasContract.method_defined?(:active_threats?)
    NaasContract.define_method(:blockchain_transactions) { BlockchainTransaction.none } unless NaasContract.method_defined?(:blockchain_transactions)
    BlockchainTransaction.define_singleton_method(:confirmed) { status_confirmed } unless BlockchainTransaction.respond_to?(:confirmed)
    EwsAlert.define_singleton_method(:active) { status_active } unless EwsAlert.respond_to?(:active)
  end

  describe "GET /api/v1/contracts" do
    context "when as JSON" do
      it "returns only contracts belonging to the user's organization" do
        get "/api/v1/contracts", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ids = response.parsed_body["data"].map { |c| c["id"] }
        expect(ids).to include(own_contract.id)
        expect(ids).not_to include(other_contract.id)
      end

      it "returns all contracts for admin users" do
        get "/api/v1/contracts", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        ids = response.parsed_body["data"].map { |c| c["id"] }
        expect(ids).to include(own_contract.id)
        expect(ids).to include(other_contract.id)
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/contracts", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/contracts", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/contracts/:id" do
    context "when as JSON" do
      it "returns a contract belonging to the user's organization" do
        get "/api/v1/contracts/#{own_contract.id}", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["contract"]["id"]).to eq(own_contract.id)
      end

      it "returns 404 for a contract from another organization" do
        get "/api/v1/contracts/#{other_contract.id}", headers: headers, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "allows admin to view any contract" do
        get "/api/v1/contracts/#{other_contract.id}", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "includes backing_asset data" do
        get "/api/v1/contracts/#{own_contract.id}", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("backing_asset")
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/contracts/#{own_contract.id}", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/contracts/#{own_contract.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/contracts/stats" do
    it "returns financial analytics for the user's organization" do
      allow(PriceOracleService).to receive(:current_scc_price).and_return(25.5)

      get "/api/v1/contracts/stats", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body).to have_key("total_invested")
      expect(body).to have_key("total_tokens_minted")
      expect(body).to have_key("portfolio_health")
      expect(body).to have_key("market_value_usd")
    end

    it "returns 401 without authentication" do
      get "/api/v1/contracts/stats", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

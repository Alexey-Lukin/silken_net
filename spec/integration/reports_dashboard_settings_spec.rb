# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reports, dashboard, and settings API" do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:token) { admin.generate_token_for(:api_access) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow(PriceOracleService).to receive(:current_scc_price).and_return(25.5)
  end

  # ---------------------------------------------------------------------------
  # ReportsController
  # ---------------------------------------------------------------------------
  describe "Reports API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    it "GET /api/v1/reports returns summary data" do
      get "/api/v1/reports",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["organization"]).to eq(organization.name)
      expect(json["summary"]).to be_present
      expect(json["available_reports"]).to include("carbon_absorption", "financial_summary")
    end

    it "GET /api/v1/reports/carbon_absorption returns carbon data as JSON" do
      get "/api/v1/reports/carbon_absorption",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["report"]).to eq("carbon_absorption")
      expect(json["data"]).to include("total_carbon_points", "wallets_count")
    end

    it "GET /api/v1/reports/carbon_absorption returns CSV" do
      get "/api/v1/reports/carbon_absorption",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/csv" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/csv")
    end

    it "GET /api/v1/reports/financial_summary returns financial data" do
      naas = create(:naas_contract, organization: organization, cluster: cluster)
      create(:blockchain_transaction, wallet: wallet, status: :confirmed, amount: 10.0)

      get "/api/v1/reports/financial_summary",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["report"]).to eq("financial_summary")
      expect(json["data"]["blockchain_transactions"]).to include("total", "confirmed", "pending", "failed")
    end

    it "GET /api/v1/reports/financial_summary returns CSV" do
      get "/api/v1/reports/financial_summary",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/csv" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/csv")
    end
  end

  # ---------------------------------------------------------------------------
  # DashboardController
  # ---------------------------------------------------------------------------
  describe "Dashboard API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family, status: :active) }

    it "GET /api/v1/dashboard returns aggregated stats" do
      get "/api/v1/dashboard",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["trees"]).to include("total", "active", "health_avg")
      expect(json["economy"]).to include("total_scc")
      expect(json["security"]).to include("active_alerts")
      expect(json["energy"]).to include("avg_voltage", "status")
    end
  end

  # ---------------------------------------------------------------------------
  # SettingsController
  # ---------------------------------------------------------------------------
  describe "Settings API" do
    it "GET /api/v1/settings returns organization config" do
      get "/api/v1/settings",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["organization"]["name"]).to eq(organization.name)
      expect(json["organization"]["billing_email"]).to eq(organization.billing_email)
    end

    it "PATCH /api/v1/settings updates organization" do
      patch "/api/v1/settings",
            params: { organization: { name: "Updated Forest Corp", billing_email: "new@forest.org" } },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      organization.reload
      expect(organization.name).to eq("Updated Forest Corp")
      expect(organization.billing_email).to eq("new@forest.org")
    end

    it "returns 403 for non-admin users" do
      investor = create(:user, :investor, organization: organization)
      inv_token = investor.generate_token_for(:api_access)

      get "/api/v1/settings",
          headers: { "Authorization" => "Bearer #{inv_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # NotificationsController
  # ---------------------------------------------------------------------------
  describe "Notifications API" do
    it "GET /api/v1/notifications/settings returns channels" do
      get "/api/v1/notifications/settings",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["channels"]).to include("email", "phone")
    end

    it "PATCH /api/v1/notifications/settings updates phone" do
      patch "/api/v1/notifications/settings",
            params: { phone_number: "+380501234567" },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(admin.reload.phone_number).to eq("+380501234567")
    end
  end

  # ---------------------------------------------------------------------------
  # SystemHealthController
  # ---------------------------------------------------------------------------
  describe "System Health API" do
    it "GET /api/v1/system_health returns health status" do
      get "/api/v1/system_health",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["checked_at"]).to be_present
      expect(json["database"]["connected"]).to be true
      expect(json["sidekiq"]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # ContractsController
  # ---------------------------------------------------------------------------
  describe "Contracts API" do
    let!(:naas) { create(:naas_contract, organization: organization, cluster: cluster) }

    it "GET /api/v1/contracts returns paginated list" do
      get "/api/v1/contracts",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
      expect(json["pagy"]).to include("page", "count")
    end

    it "GET /api/v1/contracts/:id returns contract details" do
      get "/api/v1/contracts/#{naas.id}",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["contract"]["id"]).to eq(naas.id)
      expect(json["backing_asset"]).to include("cluster_health")
    end

    it "GET /api/v1/contracts/stats returns portfolio stats" do
      get "/api/v1/contracts/stats",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("total_invested", "portfolio_health", "market_value_usd")
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reports, dashboard, and settings API" do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:token) { admin.generate_token_for(:api_access) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
      .and_return(total_minted: 500_000, total_burned: 150_000)
  end

  # ---------------------------------------------------------------------------
  # ReportsController
  # ---------------------------------------------------------------------------
  describe "Reports API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    it "GET /reports returns summary data" do
      get "/reports",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["organization"]).to eq(organization.name)
      expect(json["summary"]).to be_present
      expect(json["available_reports"]).to include("carbon_absorption", "financial_summary")
    end

    it "GET /reports/carbon_absorption returns carbon data as JSON" do
      get "/reports/carbon_absorption",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["report"]).to eq("carbon_absorption")
      expect(json["data"]).to include("total_carbon_points", "wallets_count")
    end

    it "GET /reports/carbon_absorption returns CSV" do
      get "/reports/carbon_absorption",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/csv" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/csv")
    end

    it "GET /reports/financial_summary returns financial data" do
      naas = create(:naas_contract, organization: organization, cluster: cluster)
      create(:blockchain_transaction, wallet: wallet, status: :confirmed, amount: 10.0)

      get "/reports/financial_summary",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["report"]).to eq("financial_summary")
      expect(json["data"]["blockchain_transactions"]).to include("total", "confirmed", "pending", "failed")
    end

    it "GET /reports/financial_summary returns CSV" do
      get "/reports/financial_summary",
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

    it "GET /dashboard returns aggregated stats" do
      get "/dashboard",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["trees"]).to include("total", "active", "health_avg")
      expect(json["economy"]).to include("total_scc")
      expect(json["security"]).to include("active_alerts")
      # [ARCH.84/ARCH.99] `status` знято: вердикт про запас енергії на шині,
      # яку BQ25570 сам стабілізує на 3.3 В, був фабрикацією за конструкцією.
      expect(json["energy"]).to include("avg_voltage")
      expect(json["energy"]).not_to include("status")
    end
  end

  # ---------------------------------------------------------------------------
  # SettingsController
  # ---------------------------------------------------------------------------
  describe "Settings API" do
    it "GET /settings returns organization config" do
      get "/settings",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["organization"]["name"]).to eq(organization.name)
      expect(json["organization"]["billing_email"]).to eq(organization.billing_email)
    end

    it "PATCH /settings updates organization" do
      patch "/settings",
            params: { organization: { name: "Updated Forest Corp", billing_email: "new@forest.org" } },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      organization.reload
      expect(organization.name).to eq("Updated Forest Corp")
      expect(organization.billing_email).to eq("new@forest.org")
    end

    it "returns 403 for non-admin users" do
      subscriber = create(:user, :subscriber, organization: organization)
      inv_token = subscriber.generate_token_for(:api_access)

      get "/settings",
          headers: { "Authorization" => "Bearer #{inv_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # NotificationsController
  # ---------------------------------------------------------------------------
  describe "Notifications API" do
    it "GET /notifications/settings returns channels" do
      get "/notifications/settings",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["channels"]).to include("email", "push_token")
    end

  end

  # ---------------------------------------------------------------------------
  # SystemHealthController
  # ---------------------------------------------------------------------------
  describe "System Health API" do
    it "GET /system_health returns health status" do
      get "/system_health",
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

    it "GET /contracts returns paginated list" do
      get "/contracts",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
      expect(json["pagy"]).to include("page", "count")
    end

    it "GET /contracts/:id returns contract details" do
      get "/contracts/#{naas.id}",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["contract"]["id"]).to eq(naas.id)
      expect(json["backing_asset"]).to include("cluster_health")
    end

    it "GET /contracts/stats returns portfolio stats" do
      get "/contracts/stats",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("total_contracted", "cluster_health", "attested_value_usd")
    end
  end
end

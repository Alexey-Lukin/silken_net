# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe Api::V1::ReportsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "GET /api/v1/reports" do
    it "returns a summary report for the organization" do
      get "/api/v1/reports", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["organization"]).to eq(organization.name)
      expect(body["summary"]).to include("total_trees", "health_score", "total_carbon_points")
      expect(body["available_reports"]).to include("carbon_absorption", "financial_summary")
    end
  end

  describe "GET /api/v1/reports/carbon_absorption" do
    it "returns a carbon absorption report as JSON" do
      get "/api/v1/reports/carbon_absorption", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("carbon_absorption")
      expect(body["data"]).to include("total_carbon_points", "wallets_count")
    end

    it "returns a carbon absorption report as CSV" do
      get "/api/v1/reports/carbon_absorption.csv", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")

      rows = CSV.parse(response.body)
      expect(rows[0]).to eq([ "Carbon Absorption Report" ])
      expect(rows[1][0]).to eq("Organization")
      expect(rows[1][1]).to eq(organization.name)
      expect(rows[4]).to eq(%w[Metric Value])
      expect(rows[5][0]).to eq("Total Carbon Points")
    end

    it "returns a carbon absorption report as PDF" do
      get "/api/v1/reports/carbon_absorption.pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end

  describe "GET /api/v1/reports/financial_summary" do
    before do
      allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
        .and_return(total_minted: 500_000, total_burned: 150_000)
    end

    it "returns a financial summary report as JSON" do
      get "/api/v1/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("financial_summary")
      expect(body["data"]).to include("total_contracted", "blockchain_transactions")
    end

    it "includes network_emission data in JSON response (premiums DB-sourced from NaaS contracts)" do
      # [SEC.1] total_premiums_usdc now comes from the DB (5% of activated NaaS funding),
      # not a never-emitted on-chain PremiumPaid event. 600_000 funding × 5% = 30_000.
      create(:naas_contract, status: :active, organization: organization,
                             cluster: create(:cluster, organization: organization), total_funding: 600_000)

      get "/api/v1/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ry = response.parsed_body.dig("data", "network_emission")
      expect(ry).to include(
        "total_minted_scc" => 500_000,
        "total_burned_scc" => 150_000,
        "total_premiums_usdc" => 30_000,
        "net_deflation" => -350_000
      )
    end

    it "returns a financial summary report as CSV" do
      get "/api/v1/reports/financial_summary.csv", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")

      rows = CSV.parse(response.body)
      expect(rows[0]).to eq([ "Financial Summary Report" ])
      expect(rows[1][0]).to eq("Organization")
      expect(rows[1][1]).to eq(organization.name)
      expect(rows[4]).to eq(%w[Metric Value])
      expect(rows[5][0]).to eq("Total Contracted")
    end

    it "includes network_emission data in CSV response" do
      get "/api/v1/reports/financial_summary.csv", headers: headers

      csv_text = response.body
      expect(csv_text).to include("Network Emission (DePIN/ReFi)")
      expect(csv_text).to include("Total Minted SCC")
      expect(csv_text).to include("Total Burned SCC")
      expect(csv_text).to include("Total Premiums USDC")
      expect(csv_text).to include("Net Deflation")
    end

    it "returns a financial summary report as PDF" do
      get "/api/v1/reports/financial_summary.pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to start_with("%PDF")
    end

    context "when TheGraph service is unavailable" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(TheGraph::QueryService::QueryError, "connection refused")
      end

      it "returns zero defaults for network_emission" do
        get "/api/v1/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include(
          "total_minted_scc" => 0,
          "total_burned_scc" => 0,
          "total_premiums_usdc" => 0,
          "net_deflation" => 0
        )
      end
    end

    context "when network emission fetch raises a generic StandardError" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(StandardError, "network timeout")
      end

      it "returns zero defaults for network_emission on generic error" do
        get "/api/v1/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include(
          "total_minted_scc" => 0,
          "total_burned_scc" => 0,
          "total_premiums_usdc" => 0,
          "net_deflation" => 0
        )
      end
    end

    context "when TheGraph is down but NaaS premiums exist (DB-sourced)" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(TheGraph::QueryService::QueryError, "connection refused")
      end

      it "still reports DB premiums while minted/burned fall back to 0" do
        # [SEC.1] Premiums are DB-sourced, decoupled from the subgraph — a GraphQL
        # outage zeroes minted/burned/net_deflation but NOT a known premium.
        create(:naas_contract, status: :active, organization: organization,
                               cluster: create(:cluster, organization: organization), total_funding: 200_000)

        get "/api/v1/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include(
          "total_minted_scc" => 0,
          "total_burned_scc" => 0,
          "total_premiums_usdc" => 10_000,
          "net_deflation" => 0
        )
      end
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/reports", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for carbon_absorption" do
      get "/api/v1/reports/carbon_absorption", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for financial_summary" do
      get "/api/v1/reports/financial_summary", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

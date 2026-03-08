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
    it "returns a financial summary report as JSON" do
      get "/api/v1/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("financial_summary")
      expect(body["data"]).to include("total_invested", "blockchain_transactions")
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
      expect(rows[5][0]).to eq("Total Invested")
    end

    it "returns a financial summary report as PDF" do
      get "/api/v1/reports/financial_summary.pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end
end

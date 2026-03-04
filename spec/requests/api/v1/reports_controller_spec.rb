# frozen_string_literal: true

require "rails_helper"

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
    it "returns a carbon absorption report" do
      get "/api/v1/reports/carbon_absorption", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("carbon_absorption")
      expect(body["data"]).to include("total_carbon_points", "wallets_count")
    end
  end

  describe "GET /api/v1/reports/financial_summary" do
    it "returns a financial summary report" do
      get "/api/v1/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("financial_summary")
      expect(body["data"]).to include("total_invested", "blockchain_transactions")
    end
  end
end

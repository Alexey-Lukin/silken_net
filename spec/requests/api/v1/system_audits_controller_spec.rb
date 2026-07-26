# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SystemAuditsController, type: :request do
  let(:organization) { create(:organization) }
  # ChainAuditService = платформо-глобальний db↔chain сигнал → лише admin+ (SEC).
  let(:user) { create(:user, :admin, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:audit_result) do
    ChainAuditService::Result.new(
      db_total: 1000.0,
      chain_total: 999.9999,
      delta: 0.0001,
      critical: false,
      checked_at: Time.current
    )
  end

  before do
    allow(ChainAuditService).to receive(:call).and_return(audit_result)
  end

  describe "GET /api/v1/system_audits" do
    context "when as JSON" do
      it "returns the audit results" do
        get "/api/v1/system_audits", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body["db_total"]).to eq(1000.0)
        expect(body["chain_total"]).to eq(999.9999)
        expect(body["delta"]).to eq(0.0001)
        expect(body["critical"]).to be false
        expect(body["checked_at"]).to be_present
      end

      it "reports critical when delta is large" do
        critical_audit = ChainAuditService::Result.new(
          db_total: 1000.0,
          chain_total: 990.0,
          delta: 10.0,
          critical: true,
          checked_at: Time.current
        )
        allow(ChainAuditService).to receive(:call).and_return(critical_audit)

        get "/api/v1/system_audits", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["critical"]).to be true
      end

      it "includes all expected fields in the response" do
        get "/api/v1/system_audits", headers: headers, as: :json
        body = response.parsed_body
        expect(body.keys).to contain_exactly("db_total", "chain_total", "delta", "critical", "checked_at")
      end

      it "returns correct types for all fields" do
        get "/api/v1/system_audits", headers: headers, as: :json
        body = response.parsed_body
        expect(body["db_total"]).to be_a(Numeric)
        expect(body["chain_total"]).to be_a(Numeric)
        expect(body["delta"]).to be_a(Numeric)
        expect(body["critical"]).to be_in([ true, false ])
        expect(body["checked_at"]).to be_a(String)
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/system_audits", headers: headers
        expect(response).to have_http_status(:ok)
      end

      it "includes text/html content type" do
        get "/api/v1/system_audits", headers: { **headers, "Accept" => "text/html" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/html")
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/system_audits", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "delegates to ChainAuditService.call" do
      get "/api/v1/system_audits", headers: headers, as: :json
      expect(ChainAuditService).to have_received(:call)
    end
  end
end

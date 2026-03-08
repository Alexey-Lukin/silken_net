# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SystemAuditsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
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
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/system_audits", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/system_audits", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

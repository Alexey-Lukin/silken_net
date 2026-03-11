# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AuditLogsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:admin_user) { create(:user, :admin, organization: organization) }
  let(:regular_user) { create(:user, organization: organization) }
  let(:other_admin) { create(:user, :admin, organization: other_organization) }
  let(:admin_token) { admin_user.generate_token_for(:api_access) }
  let(:regular_token) { regular_user.generate_token_for(:api_access) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:regular_headers) { { "Authorization" => "Bearer #{regular_token}" } }

  let!(:own_log) { create(:audit_log, user: admin_user, organization: organization) }
  let!(:other_log) { create(:audit_log, user: other_admin, organization: other_organization) }

  describe "GET /api/v1/audit_logs" do
    it "returns only audit logs belonging to the user's organization" do
      get "/api/v1/audit_logs", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |l| l["id"] }
      expect(ids).to include(own_log.id)
      expect(ids).not_to include(other_log.id)
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/audit_logs", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/audit_logs/:id" do
    it "returns a specific audit log from the user's organization" do
      get "/api/v1/audit_logs/#{own_log.id}", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_log.id)
    end

    it "returns 404 for an audit log from another organization" do
      get "/api/v1/audit_logs/#{other_log.id}", headers: admin_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{admin_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/audit_logs", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/audit_logs/#{own_log.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

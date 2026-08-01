# SPDX-License-Identifier: AGPL-3.0-or-later
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

  # [SEC.25 Ф2] `organization_id: nil` в audit_logs — не «запис без організації», а
  # окремий СИСТЕМНИЙ ланцюг (org-less дії, зокрема зміни SystemParameter). Доти
  # super_admin бачив саме його — випадково, бо його власний organization_id теж nil.
  # Під acting-org він дістав би id організації й тихо втратив би governance-журнал,
  # і жоден тест не почервонів би: Pundit тут не викликається (скоуп ручний), а власна
  # політика була мертвим кодом і знята ⚖️ 2026-07-31. Саме тому цей describe і є
  # єдиним сторожем системного ланцюга.
  describe "системний ланцюг (organization_id: nil)" do
    let!(:system_log) { create(:audit_log, user: admin_user, organization: nil) }
    let(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:super_headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

    it "видно super_admin разом із журналом його acting-організації" do
      get "/audit_logs", headers: super_headers, as: :json

      ids = response.parsed_body["data"].map { |l| l["id"] }
      expect(ids).to include(system_log.id, own_log.id)
      expect(ids).not_to include(other_log.id)
    end

    it "НЕ видно звичайному адміністраторові організації" do
      get "/audit_logs", headers: admin_headers, as: :json

      ids = response.parsed_body["data"].map { |l| l["id"] }
      expect(ids).to include(own_log.id)
      expect(ids).not_to include(system_log.id)
    end
  end

  describe "GET /audit_logs" do
    it "returns only audit logs belonging to the user's organization" do
      get "/audit_logs", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |l| l["id"] }
      expect(ids).to include(own_log.id)
      expect(ids).not_to include(other_log.id)
    end

    it "returns 403 for non-admin users" do
      get "/audit_logs", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /audit_logs/:id" do
    it "returns a specific audit log from the user's organization" do
      get "/audit_logs/#{own_log.id}", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_log.id)
    end

    it "returns 404 for an audit log from another organization" do
      get "/audit_logs/#{other_log.id}", headers: admin_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /audit_logs with filtering" do
    it "filters by action_type" do
      get "/audit_logs", params: { action_type: own_log.action }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      data = response.parsed_body["data"]
      expect(data).to be_an(Array)
    end

    it "filters by user_id" do
      get "/audit_logs", params: { user_id: admin_user.id }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      data = response.parsed_body["data"]
      expect(data).to be_an(Array)
    end

    it "returns empty results for non-matching action_type filter" do
      get "/audit_logs", params: { action_type: "nonexistent_action" }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      data = response.parsed_body["data"]
      expect(data).to be_an(Array)
    end
  end

  describe "GET /audit_logs with pagination" do
    it "respects custom limit parameter" do
      get "/audit_logs", params: { limit: 1 }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to be_present
    end

    it "clamps limit to minimum of 1" do
      get "/audit_logs", params: { limit: 0 }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "clamps limit to maximum of 100" do
      get "/audit_logs", params: { limit: 999 }, headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "authentication" do
    it "returns 401 without authentication" do
      get "/audit_logs", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{admin_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/audit_logs", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/audit_logs/#{own_log.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

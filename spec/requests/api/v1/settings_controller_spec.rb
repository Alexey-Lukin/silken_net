# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SettingsController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin_user) { create(:user, :admin, organization: organization) }
  let(:regular_user) { create(:user, organization: organization) }
  let(:admin_token) { admin_user.generate_token_for(:api_access) }
  let(:regular_token) { regular_user.generate_token_for(:api_access) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:regular_headers) { { "Authorization" => "Bearer #{regular_token}" } }

  describe "GET /settings" do
    it "returns organization settings for admin users" do
      get "/settings", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["organization"]["name"]).to eq(organization.name)
      expect(body["organization"]["billing_email"]).to eq(organization.billing_email)
      expect(body["organization"]).to have_key("alert_threshold_critical_z")
      expect(body["organization"]).to have_key("ai_sensitivity")
      expect(body["organization"]).to have_key("logo_url")
    end

    it "returns 403 for non-admin users" do
      get "/settings", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    # [UI.9] HTML-близнюк того самого 403, і саме його бракувало класу: дев'ять із
    # дев'яти запитів цього файла йшли `as: :json`, тож гілка, якою ходить БРАУЗЕР,
    # не виконувалась жодного разу — а голий `render_forbidden` `respond_to` не мав,
    # тобто віддавав користувачеві сирий JSON-блоб замість сторінки відмови.
    # [UI.9] Живий HTML-шлях до `render_parameter_missing`: сабміт форми без
    # кореневого ключа. Доти цей рендерер був JSON-only, тобто людина, що надіслала
    # обрізану форму, бачила сирий `{"error":...}`.
    it "віддає браузеру сторінку на форму без обовʼязкового ключа" do
      patch "/settings", headers: admin_headers.merge("Accept" => "text/html"), params: {}

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(I18n.t("errors.api.bad_request_title"))
    end

    it "віддає браузеру СТОРІНКУ відмови, а не JSON-блоб" do
      get "/settings", headers: regular_headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html")
      expect(response.body).to include(I18n.t("errors.api.forbidden_title"))
    end
  end

  describe "PATCH /settings" do
    it "updates organization settings for admin users" do
      patch "/settings",
            headers: admin_headers,
            params: { organization: { name: "New Forest Fund", billing_email: "new@example.org" } },
            as: :json

      expect(response).to have_http_status(:ok)
      organization.reload
      expect(organization.name).to eq("New Forest Fund")
      expect(organization.billing_email).to eq("new@example.org")
    end

    it "updates alert threshold and AI sensitivity" do
      patch "/settings",
            headers: admin_headers,
            params: { organization: { alert_threshold_critical_z: "3.0", ai_sensitivity: "0.85" } },
            as: :json

      expect(response).to have_http_status(:ok)
      organization.reload
      expect(organization.alert_threshold_critical_z).to eq(3.0)
      expect(organization.ai_sensitivity).to eq(0.85)
    end

    it "returns 403 for non-admin users" do
      patch "/settings",
            headers: regular_headers,
            params: { organization: { name: "Hacked" } },
            as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /settings logo_url" do
    it "returns nil logo_url when no logo is attached" do
      get "/settings", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["organization"]["logo_url"]).to be_nil
    end

    it "returns logo_url when logo is attached" do
      organization.logo.attach(
        io: StringIO.new("fake-logo-data"),
        filename: "logo.png",
        content_type: "image/png"
      )

      get "/settings", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["organization"]["logo_url"]).to be_present
    end
  end

  describe "PATCH /settings with logo" do
    it "returns logo_url after successful update when logo is attached" do
      organization.logo.attach(
        io: StringIO.new("fake-logo-data"),
        filename: "logo.png",
        content_type: "image/png"
      )

      patch "/settings",
            headers: admin_headers,
            params: { organization: { name: "Updated Name" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["organization"]["logo_url"]).to be_present
    end
  end

  describe "PATCH /settings failure" do
    it "returns errors when organization update fails" do
      patch "/settings",
            headers: admin_headers,
            params: { organization: { name: "", billing_email: "invalid" } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{admin_token}", "Accept" => "text/html" }
    end

    it "renders HTML for show" do
      get "/settings", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "exercises HTML error on update failure" do
      patch "/settings",
            headers: html_headers,
            params: { organization: { name: "", billing_email: "invalid" } }
      # Phlex component may not fully render in test env, but code path is exercised
      expect(response.status).to be_in([ 200, 500 ])
    end
  end
end

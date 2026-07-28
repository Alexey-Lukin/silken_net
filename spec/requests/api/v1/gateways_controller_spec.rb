# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::GatewaysController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_gateway) { create(:gateway, cluster: own_cluster) }
  let!(:other_gateway) { create(:gateway, cluster: other_cluster) }

  describe "GET /api/v1/gateways" do
    it "returns only gateways belonging to the user's organization" do
      get "/api/v1/gateways", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |g| g["id"] }
      expect(ids).to include(own_gateway.id)
      expect(ids).not_to include(other_gateway.id)
    end

    it "returns pagination metadata" do
      get "/api/v1/gateways", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to be_present
    end

    it "returns 401 without authentication" do
      get "/api/v1/gateways", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gateways/:id" do
    it "returns a gateway belonging to the user's organization" do
      get "/api/v1/gateways/#{own_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_gateway.id)
    end

    it "returns 404 for a gateway from another organization" do
      get "/api/v1/gateways/#{other_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent gateway" do
      get "/api/v1/gateways/999999", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/gateways", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/gateways/#{own_gateway.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # Пін на ІМʼЯ стріму, а не на скоуп — і різницю варто тримати в голові.
    # Скоуп цього сайту доведений сусіднім прикладом («returns 404 for a gateway
    # from another organization»), і доведений ТРАНЗИТИВНО: org-скоуплений `find`
    # стоїть ПЕРЕД `respond_to`, тож чужий шлюз кидає `RecordNotFound` до
    # розгалуження форматів і HTML-гілки не досягає жодним шляхом.
    #
    # 🔴 Недоведеним лишалось саме імʼя: `ota_channel_{uid}` org-токена не несе,
    # а жоден приклад цього файлу HTML-гілку зі стрімом не читав (усі йшли
    # `as: :json`). Тобто інтерполяція не того атрибута або зашите константне
    # імʼя лишились би зеленими — та сама `as: :json`-сліпота, що вже коштувала
    # тихого no-op'а на `AlertsController#resolve` (`00_07` UI.4).
    #
    # ⚠️ Форма — РІВНІСТЬ МНОЖИНИ (`eq`, не `include`): дефект імені без
    # org-токена виглядає як ЗАЙВИЙ стрім на сторінці, а не як відсутній свій,
    # тож `include` пройшов би. `other_gateway` існує в БД (`let!` вище), отже
    # зайвому стріму реально є звідки взятись.
    it "subscribes only to the gateway's OWN OTA channel" do
      get "/api/v1/gateways/#{own_gateway.id}", headers: html_headers

      streams = response.body.scan(/signed-stream-name="([^"]+)"/).flatten
                        .map { |name| Turbo::StreamsChannel.verified_stream_name(name) }
      expect(streams).to eq([ "ota_channel_#{own_gateway.uid}" ])
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ClustersController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  describe "GET /api/v1/clusters" do
    it "returns only clusters belonging to the user's organization" do
      get "/api/v1/clusters", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(own_cluster.id)
      expect(ids).not_to include(other_cluster.id)
    end

    it "returns pagination metadata" do
      get "/api/v1/clusters", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to be_present
    end

    it "returns 401 without authentication" do
      get "/api/v1/clusters", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/clusters/:id" do
    it "returns a cluster belonging to the user's organization" do
      get "/api/v1/clusters/#{own_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_cluster.id)
    end

    it "returns 404 for a cluster from another organization" do
      get "/api/v1/clusters/#{other_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent cluster" do
      get "/api/v1/clusters/999999", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # [SEC.25 Ф2] Перемикання acting-організації пінилось рівно для ОДНОГО ресурсу
  # (`wallets`), тоді як асоціативним скоупом живуть 19 контролерів. Копіювати цей
  # приклад у всі 19 не варто — вони ходять через ОДИН резолвер
  # (`BaseController#resolve_acting_organization`), тож 18 копій стерегли б той самий
  # рядок. Але теза «спільний метод покриває решту» сама потребувала доказу: без
  # жодного другого піна локальний обхід резолвера в одному контролері
  # (`current_user.organization` замість `acting_organization!`) лишив би сюїту
  # зеленою. Цей приклад — той доказ, на ДРУГОМУ ресурсі; далі множити не треба.
  # ⚠️ Cookie-логін тут обовʼязковий: `switch` вимагає сесії й на Bearer віддає 403.
  describe "перемикання acting-організації [SEC.25 Ф2]" do
    let!(:super_admin) { create(:user, :super_admin, organization: organization) }

    before do
      post "/api/v1/login",
           params: { email: super_admin.email_address, password: "password12345" },
           as: :json
    end

    it "перемикає те, що super_admin реально бачить" do
      get "/api/v1/clusters", as: :json
      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(own_cluster.id)
      expect(ids).not_to include(other_cluster.id)

      post "/api/v1/organizations/#{other_organization.id}/switch", as: :json
      expect(response).to have_http_status(:ok)

      get "/api/v1/clusters", as: :json
      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(other_cluster.id)
      expect(ids).not_to include(own_cluster.id)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/clusters", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/clusters/#{own_cluster.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

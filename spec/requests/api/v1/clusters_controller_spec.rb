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

  describe "GET /clusters" do
    it "returns only clusters belonging to the user's organization" do
      get "/clusters", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(own_cluster.id)
      expect(ids).not_to include(other_cluster.id)
    end

    it "returns pagination metadata" do
      get "/clusters", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to be_present
    end

    it "returns 401 without authentication" do
      get "/clusters", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /clusters/:id" do
    it "returns a cluster belonging to the user's organization" do
      get "/clusters/#{own_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_cluster.id)
    end

    it "returns 404 for a cluster from another organization" do
      get "/clusters/#{other_cluster.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent cluster" do
      get "/clusters/999999", headers: headers, as: :json
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
      post "/login",
           params: { email: super_admin.email_address, password: "password12345" },
           as: :json
    end

    it "перемикає те, що super_admin реально бачить" do
      get "/clusters", as: :json
      ids = response.parsed_body["data"].map { |c| c["id"] }
      expect(ids).to include(own_cluster.id)
      expect(ids).not_to include(other_cluster.id)

      post "/organizations/#{other_organization.id}/switch", as: :json
      expect(response).to have_http_status(:ok)

      get "/clusters", as: :json
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
      get "/clusters", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/clusters/#{own_cluster.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # 🔴 [ARCH.84] Проводка пари покриття доводиться ЛИШЕ тут: компонентна спека
    # рендерить повз маршрутизатор І повз викликача, тож вона однаково зелена і
    # тоді, коли контролер узагалі не шукає інсайту (`04_06 §B.2` BP #14).
    # Приклад вище тримає ДРУГУ половину — інсайту немає, `&.` іде в `nil`, і
    # сторінка мовчить про покриття; разом вони пінять обидві гілки.
    it "wires the coverage of the day's cluster insight into the rendered page" do
      own_cluster.update_column(:health_index, 0.87)
      create(:ai_insight, analyzable: own_cluster, insight_type: :daily_health_summary,
                          target_date: AiInsight.reporting_date, stress_index: 0.13,
                          reasoning: { "measured_trees" => 1, "total_trees" => 5 })

      get "/clusters/#{own_cluster.id}", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("ui.measurement.coverage", measured: 1, total: 5))
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TreesController, type: :request do
  before do
    silence_broadcasts!(:tree_map)
  end

  def build_chronicle_pagy(page: 1, limit: 20, count: 2, pages: 1)
    OpenStruct.new(
      page: page,
      limit: limit,
      count: count,
      last: pages,
      from: 1,
      to: count,
      previous: page > 1 ? page - 1 : nil,
      next: page < pages ? page + 1 : nil,
      vars: { items: limit }
    ).tap do |pagy|
      pagy.define_singleton_method(:series) { (1..last).to_a }
    end
  end

  def build_chronicle_entry(title:, date:, **attributes)
    OpenStruct.new(
      {
        title: title,
        description: "Entry description",
        event_type: :telemetry,
        icon: "🌿",
        severity: :info,
        source_type: "TelemetryLog",
        source_id: 123,
        date: date
      }.merge(attributes)
    )
  end

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }
  let(:html_headers) { headers.merge("Accept" => "text/html") }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_tree) { create(:tree, cluster: own_cluster) }
  let!(:other_tree) { create(:tree, cluster: other_cluster) }

  describe "GET /clusters/:cluster_id/trees" do
    it "returns trees from a cluster in the user's organization" do
      get "/clusters/#{own_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |t| t["id"] }
      expect(ids).to include(own_tree.id)
    end

    it "returns pagination metadata" do
      get "/clusters/#{own_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
    end

    it "returns 404 for a cluster from another organization" do
      get "/clusters/#{other_cluster.id}/trees", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /trees/:id" do
    it "returns a tree belonging to the user's organization" do
      get "/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tree"]["id"]).to eq(own_tree.id)
    end

    # [ARCH.84] Приклад сам зізнавався в назві («with null values») і водночас
    # вимагав `eq(0)` від однієї з чотирьох величин. Нуль тут не нейтральний:
    # `z` — координата атрактора Лоренца, а `CRITICAL_Z_MIN` = 2.0, тож нуль
    # читається як катастрофічна втрата тургору, приписана вузлу, який просто
    # ніколи не виходив в ефір. Три сусідні поля були чесні весь час.
    it "includes telemetry data with null values when no logs exist" do
      get "/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      telemetry = response.parsed_body["telemetry"]
      expect(telemetry["z_value"]).to be_nil
      expect(telemetry["temperature"]).to be_nil
      expect(telemetry["voltage"]).to be_nil
      expect(telemetry["last_sync"]).to be_nil
    end

    # ⊥ Ліхтар до піна вище: сам лише `be_nil` не розрізняє «не виміряно» і
    # «виміряний нуль», а нуль тут ДОСЯЖНИЙ — без цієї пари фікс, що поверне
    # `|| 0`, червонив би рівно один приклад і читався б як регресія формату.
    it "reports a measured zero z_value as zero, not as absence" do
      create(:telemetry_log, tree: own_tree, z_value: 0.0)

      get "/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response.parsed_body.dig("telemetry", "z_value").to_f).to eq(0.0)
      expect(response.parsed_body.dig("telemetry", "z_value")).not_to be_nil
    end

    it "includes telemetry data when logs exist" do
      create(:telemetry_log, tree: own_tree,
        z_value: 1.5, temperature_c: 25.0, voltage_mv: 3500)

      get "/trees/#{own_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      telemetry = response.parsed_body["telemetry"]
      expect(telemetry["z_value"].to_f).to eq(1.5)
      expect(telemetry["temperature"].to_f).to eq(25.0)
      expect(telemetry["voltage"].to_i).to eq(3500)
      expect(telemetry["last_sync"]).to be_present
    end

    it "returns 404 for a tree from another organization" do
      get "/trees/#{other_tree.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /trees/:id/chronicle" do
    let(:chronicle_pagy) { build_chronicle_pagy(page: 2, count: 21, pages: 2) }
    let(:dated_entry) do
      build_chronicle_entry(
        title: "Telemetry Logged",
        date: Time.zone.parse("2025-04-25 10:30:00 UTC"),
        description: "Stable readings",
        severity: :warning,
        source_id: 77
      )
    end
    let(:undated_entry) do
      build_chronicle_entry(
        title: "Maintenance Scheduled",
        date: nil,
        description: "Awaiting technician",
        event_type: :maintenance,
        icon: "🔧",
        source_type: "MaintenanceRecord",
        source_id: 99
      )
    end
    let(:expected_json_response) do
      {
        "data" => [
          {
            "date" => "2025-04-25T10:30:00Z",
            "event_type" => "telemetry",
            "icon" => "🌿",
            "title" => "Telemetry Logged",
            "description" => "Stable readings",
            "severity" => "warning",
            "source_type" => "TelemetryLog",
            "source_id" => 77
          },
          {
            "date" => nil,
            "event_type" => "maintenance",
            "icon" => "🔧",
            "title" => "Maintenance Scheduled",
            "description" => "Awaiting technician",
            "severity" => "info",
            "source_type" => "MaintenanceRecord",
            "source_id" => 99
          }
        ],
        "pagy" => {
          "page" => 2,
          "limit" => 20,
          "count" => 21,
          "pages" => 2
        }
      }
    end

    before do
      allow(TreeChronicleService).to receive(:call).and_return(
        { entries: [ dated_entry, undated_entry ], pagy: chronicle_pagy }
      )
    end

    it "returns chronicle entries and pagination metadata as JSON" do
      get "/trees/#{own_tree.id}/chronicle", params: { page: 2 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(TreeChronicleService).to have_received(:call).with(tree: own_tree, page: 2, per_page: 20)
      expect(response.parsed_body).to eq(expected_json_response)
    end

    it "renders the chronicle turbo frame as HTML" do
      get "/trees/#{own_tree.id}/chronicle", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      expect(TreeChronicleService).to have_received(:call).with(tree: own_tree, page: nil, per_page: 20)
    end

    it "returns 404 for a tree from another organization" do
      get "/trees/#{other_tree.id}/chronicle", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  context "with format.html responses" do
    # [UI.3] 🔴 Ліхтар на РОЗМІР колекції, а не декорація навколо smoke-піна.
    # Prosopite сканує КОЖЕН request-приклад (`rails_helper`), але ловить лише
    # ПОВТОРЕНИЙ запит — тобто йому потрібні щонайменше ДВА рядки. Доти ця
    # сторінка рендерилась із рівно одним деревом, і детектор мовчав не тому, що
    # N+1 не було, а тому, що не було другого рядка: `Trees::Index#tree_status_led`
    # кликав `under_threat?` на кожен рядок, і кожен виклик бив у БД власним
    # EXISTS. Гейт існував, знезброїла його ФІКСТУРА.
    # ⛔ Не зводь колекцію назад до одного запису: приклад лишиться зеленим, але
    # перестане щось міряти — а порожній/одиничний скоуп невідрізнимий від
    # «дефекту немає» ([`04_06 §B.1`](04_06_Testing_Guide_and_Coverage)).
    it "renders HTML for index" do
      # `Prosopite.pause` — рівно на ПІДГОТОВКУ, ніколи на запит: `Tree` має
      # `build_default_wallet`/`ensure_calibration` в `after_create`, тож саме
      # створення двох дерев виглядає для детектора як N+1 (усталений патерн,
      # прецедент — `spec/integration/insight_aggregation_flow_spec.rb`). Межа
      # несуча: `resume` мусить стояти ДО `get`, інакше пауза знезброїть рівно ту
      # перевірку, заради якої фікстуру й розширено.
      Prosopite.pause
      siblings = create_list(:tree, 2, cluster: own_cluster, status: :active)
      create(:ews_alert, tree: siblings.first, cluster: own_cluster, status: :active)
      Prosopite.resume

      get "/clusters/#{own_cluster.id}/trees", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      # Сітка друкує ХВІСТ ідентифікатора (`did.last(6)`), не весь — ліхтар
      # мусить питати те, що сторінка справді виводить, інакше він міряє власну
      # здогадку про розмітку.
      siblings.each { |tree| expect(response.body).to include(tree.did.last(6)) }
    end

    it "renders HTML for show" do
      get "/trees/#{own_tree.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end

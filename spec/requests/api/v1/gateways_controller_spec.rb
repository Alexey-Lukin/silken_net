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

  describe "GET /gateways" do
    it "returns only gateways belonging to the user's organization" do
      get "/gateways", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |g| g["id"] }
      expect(ids).to include(own_gateway.id)
      expect(ids).not_to include(other_gateway.id)
    end

    it "returns pagination metadata" do
      get "/gateways", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pagy"]).to be_present
    end

    it "returns 401 without authentication" do
      get "/gateways", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # [PERF.1 (а)] Преload `has_one` знято на користь `latest_per_gateway` (LATERAL).
    # Обидві половини заміни треба доводити ОКРЕМО: що відповідь та сама, і що
    # виграш справді є — інакше «оптимізацію» не відрізнити від тихої зміни даних.
    describe "останній пульс на шлюз" do
      # ДВА шлюзи × ДВА пульси — менший набір не показує нічого: на одному рядку
      # N+1 недосяжний за побудовою (Prosopite нема на чому спрацювати), а на
      # одному лозі «останній» не відрізнити від «будь-який» (`04_06 §B.2` BP 21).
      let!(:second_gateway) { create(:gateway, cluster: own_cluster) }

      before do
        create(:gateway_telemetry_log, gateway: own_gateway, cellular_signal_csq: 5, created_at: 2.hours.ago)
        create(:gateway_telemetry_log, gateway: own_gateway, cellular_signal_csq: 27, created_at: 1.minute.ago)
        create(:gateway_telemetry_log, gateway: second_gateway, cellular_signal_csq: 8, created_at: 3.hours.ago)
        create(:gateway_telemetry_log, gateway: second_gateway, cellular_signal_csq: 20, created_at: 2.minutes.ago)
      end

      # Чотири відсотки РІЗНІ свідомо: інакше пін проходив би через сусідній
      # вузол, і зіпсований `ORDER BY` (найстаріший замість найновішого) лишався
      # б зеленим.
      it "renders the LATEST heartbeat of EACH gateway, never an older one" do
        get "/gateways", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("87.1")  # csq 27 — свіжий пульс шлюзу A
        expect(response.body).to include("64.5")  # csq 20 — свіжий пульс шлюзу B
        expect(response.body).not_to include("16.1") # csq 5  — старий пульс A
        expect(response.body).not_to include("25.8") # csq 8  — старий пульс B
      end

      # Виграш сам по собі: JSON-гілка телеметрії не віддає (`GatewayBlueprint` —
      # лише uid/state/last_seen_at/координати), тож преload там був чистою
      # втратою. Пін цілиться в ТАБЛИЦЮ, а не в кількість запитів: останнє
      # дрейфує від будь-якої сусідньої правки.
      it "does not touch gateway_telemetry_logs at all in the JSON branch" do
        touched = []
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          touched << payload[:sql] if payload[:sql]&.include?("gateway_telemetry_logs")
        end

        get "/gateways", headers: headers, as: :json

        ActiveSupport::Notifications.unsubscribe(sub)
        expect(response).to have_http_status(:ok)
        expect(touched).to be_empty
      end
    end
  end

  describe "GET /gateways/:id" do
    it "returns a gateway belonging to the user's organization" do
      get "/gateways/#{own_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(own_gateway.id)
    end

    it "returns 404 for a gateway from another organization" do
      get "/gateways/#{other_gateway.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent gateway" do
      get "/gateways/999999", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/gateways", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # [UI.3] Сітка флоту — найгустіший цикл у дереві (`limit(200)`), і кожен її
    # вузол кликав `under_threat?`, тобто власний EXISTS. Prosopite стоїть на
    # цьому прикладі відколи він існує й мовчав: кластер шлюзу не мав ЖОДНОГО
    # дерева, тож циклу не було взагалі. Два вузли — мінімум, при якому детектор
    # взагалі здатен побачити повтор; `did` обох у тілі — ліхтар, що вони туди
    # доїхали (без нього приклад зелений на порожній сітці).
    it "renders HTML for show" do
      # `Prosopite.pause` — рівно на ПІДГОТОВКУ, ніколи на запит: `Tree` має
      # `build_default_wallet`/`ensure_calibration` в `after_create`, тож саме
      # створення двох дерев виглядає для детектора як N+1 (усталений патерн,
      # прецедент — `spec/integration/insight_aggregation_flow_spec.rb`). Межа
      # несуча: `resume` мусить стояти ДО `get`, інакше пауза знезброїть рівно ту
      # перевірку, заради якої фікстуру й розширено.
      Prosopite.pause
      soldiers = create_list(:tree, 2, cluster: own_cluster, status: :active)
      create(:ews_alert, tree: soldiers.first, cluster: own_cluster, status: :active)
      Prosopite.resume

      get "/gateways/#{own_gateway.id}", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      soldiers.each { |tree| expect(response.body).to include(tree.did) }
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
      get "/gateways/#{own_gateway.id}", headers: html_headers

      streams = response.body.scan(/signed-stream-name="([^"]+)"/).flatten
                        .map { |name| Turbo::StreamsChannel.verified_stream_name(name) }
      expect(streams).to eq([ "ota_channel_#{own_gateway.uid}" ])
    end
  end
end

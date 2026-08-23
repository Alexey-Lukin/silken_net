# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AlertsController, type: :request do
  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    silence_broadcasts!(:alert_notify)
    allow_any_instance_of(EwsAlert).to receive(:close_associated_maintenance!)
    silence_broadcasts!(:alert_update)
  end

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, :forester, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_alert) { create(:ews_alert, :drought, cluster: own_cluster) }
  let!(:other_alert) { create(:ews_alert, :fire, cluster: other_cluster) }

  describe "GET /alerts" do
    it "returns only alerts belonging to the user's organization" do
      get "/alerts", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_alert.id)
      expect(ids).not_to include(other_alert.id)
    end

    # 🔴 [TEST.12 вісь D] Обидва приклади нижче доти міряли лише `:ok` — тобто були
    # зелені з видаленим `where`. І фікстура робила їх безнадійними навіть для піна
    # на вміст: єдина СВОЯ тривога — `:drought` (severity `medium`), а `:critical`
    # лежала в ЧУЖІЙ організації, тож `severity=critical` повертав порожній набір,
    # і приклад вітав порожнечу. Фільтр перевірний лише тоді, коли є що ВІДКИНУТИ
    # всередині вже видимого набору — інакше його роботу виконує тенант-скоуп.
    it "filters by severity" do
      own_critical = create(:ews_alert, :fire, cluster: own_cluster)

      get "/alerts", params: { severity: "critical" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_critical.id)
      expect(ids).not_to include(own_alert.id)
    end

    it "filters by cluster_id" do
      sibling_cluster = create(:cluster, organization: organization)
      sibling_alert = create(:ews_alert, :drought, cluster: sibling_cluster)

      get "/alerts", params: { cluster_id: own_cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_alert.id)
      expect(ids).not_to include(sibling_alert.id)
    end

    # =========================================================================
    # ENUM WHITELIST: status/severity hit AR enums backed by PG columns; passing
    # a non-enum string used to surface as PG::InvalidTextRepresentation (HTTP
    # 500 + Sentry spam). Both branches now respond 400 with an i18n message.
    # =========================================================================
    it "rejects bogus status with 400" do
      get "/alerts", params: { status: "bogus_status_xx" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("bogus_status_xx")
    end

    it "rejects bogus severity with 400" do
      get "/alerts", params: { severity: "nuclear" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("nuclear")
    end

    it "accepts the 'resolved' status keyword" do
      own_alert.update!(status: :resolved, resolved_at: Time.current, resolved_by: user)
      get "/alerts", params: { status: "resolved" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_alert.id)
    end
  end

  describe "GET /alerts/:id" do
    it "returns a specific alert from the user's organization" do
      get "/alerts/#{own_alert.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body["data"]
      expect(body["id"]).to eq(own_alert.id)
      expect(body).to have_key("coordinates")
    end

    it "returns 404 for an alert from another organization" do
      get "/alerts/#{other_alert.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /alerts/:id/resolve" do
    # Назва обіцяє ПОБІЧНИЙ ЕФЕКТ, а не доступ, тож пін іде на сам запис: `:ok`
    # переживає й повністю знятий `resolve!`.
    it "resolves an alert belonging to the user's organization" do
      expect(own_alert.status).not_to eq("resolved")

      patch resolve_alert_path(own_alert), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(own_alert.reload.status).to eq("resolved")
    end

    it "returns 404 for an alert from another organization" do
      patch resolve_alert_path(other_alert), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    # 🔴 Тут стояло `allow(...).to receive(:resolve!).and_return(false)` + очікування 422.
    # Приклад був ВАКУУМНИЙ: `EwsAlert#resolve!` завершується літеральним `true`, а
    # `mark_resolved!` і `whiny_persistence: true` не повертають `false` — вони КИДАЮТЬ.
    # Тобто спека пінила стан, якого не існує, і давала хибну впевненість, що гілка
    # відмови покрита. Реальний шлях — повторний клік (тротл броадкасту 5 с) — летів
    # у `rescue_from StandardError` і віддавав 500. Тепер пінимо саме його.
    it "повертає 409 на повторному закритті, а не 500" do
      patch resolve_alert_path(own_alert), headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      patch resolve_alert_path(own_alert), headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
    end

    it "на повторному закритті з браузера редиректить, а не віддає JSON" do
      patch resolve_alert_path(own_alert), headers: headers, as: :json

      patch resolve_alert_path(own_alert), headers: headers.merge("Accept" => "text/html")

      expect(response).to redirect_to(alerts_path)
      expect(response.media_type).not_to eq("application/json")
    end

    # 🔴 Ця гілка не була покрита ЖОДНИМ прикладом — усі решта йдуть `as: :json` —
    # і саме тому вона роками цілила в `alert_{id}`, тоді як `Alerts::Row`
    # рендериться з `dom_id` = `ews_alert_{id}`. Ціль не існувала в жодній
    # сторінці, replace був тихим no-op, а видимість тримав асинхронний
    # броадкаст (який ця ж спека глушить рядком вище). Пін саме на ЦІЛЬ:
    # «віддав turbo_stream» лишався б зеленим і з мертвим ідентифікатором.
    it "targets the row's real dom_id in the turbo_stream response" do
      patch resolve_alert_path(own_alert),
            headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(target="ews_alert_#{own_alert.id}"))
      expect(response.body).not_to include(%(target="alert_#{own_alert.id}"))
    end

    # 🔴 [UI.7] Тут ціль ОДНАКОВА в обох гілках (`alerts_path`), тож `redirect_to` сам
    # по собі нічого не розрізняє — дискримінатором є КЛЮЧ flash: `success` при
    # закритті ⊥ `pending` при повторному кліку (AASM::InvalidTransition → 409-гілка).
    # Доти існував лише перший приклад, і його єдиним твердженням був «якийсь 3xx»,
    # тобто дві протилежні події сюїта бачила однаково. Пара нижче — взаємні мутації.
    it "redirects a successful HTML resolve back to the list, flagged as success" do
      patch resolve_alert_path(own_alert),
            headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to redirect_to(alerts_path)
      expect(flash[:success]).to be_present
      expect(flash[:pending]).to be_blank
      expect(own_alert.reload.status).to eq("resolved")
    end

    it "flags a SECOND resolve as pending, not as success" do
      own_alert.update!(status: :resolved, resolved_at: Time.current, resolved_by: user)

      patch resolve_alert_path(own_alert),
            headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to redirect_to(alerts_path)
      expect(flash[:pending]).to be_present
      expect(flash[:success]).to be_blank
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/alerts", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # [ARCH.31] ЦІЛЬ посилання, і довести її може лише цей шар: компонентна спека
    # рендерить повз маршрутизатор І повз викликача, тож вона однаково зелена,
    # коли `Alerts::Index` забуде передати `linked:`. Доти `alert_path` не мав у
    # всьому `app/` ЖОДНОГО виклику — маршрут `GET /alerts/:id` існував, рендерив
    # SOP-панель, і дістатись її можна було тільки набравши адресу руками.
    it "реєстр веде на сторінку тривоги — вхід на SOP існує в розмітці" do
      get "/alerts", headers: html_headers
      expect(response.body).to include("href=\"/alerts/#{own_alert.id}\"")
    end

    # HTML-рендер `show` не пінив ЖОДЕН приклад цього файлу — усі йшли `as: :json`,
    # тобто найдорожча половина сторінки (операційний runbook) трималась виключно
    # на компонентній спеці, яка ходить повз контролер і повз `render_dashboard`.
    it "сторінка тривоги віддає HTML із SOP-панеллю" do
      get "/alerts/#{own_alert.id}", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      expect(response.body).to include(I18n.t("alerts.show.sop.title"))
      expect(response.body).to include(I18n.t("alerts.show.sop.steps.acknowledge.title"))
    end

    # Дзеркало піна `telemetry_controller_spec` / `dashboard_controller_spec`:
    # єдиний рядок, що вирішує ЧИЯ організація, живе в контролері, і компонентна
    # спека його не бачить (вона дістає організацію моком). Підписане імʼя стріму —
    # це capability-токен, тож видача чужого = крос-тенант живих тривог, якого
    # HTTP-відповідь не показує: витік їде вебсокетом уже після підписки.
    # ⚠️ Двоє глядачів обовʼязкові: `organization` створюється в цьому файлі
    # першою, тож підміна на `Organization.first` дорівнює їй і однокористувацький
    # приклад лишився б зеленим. Ловить лише РІЗНИЦЯ. `eq` (не `include`) тримає
    # заразом і другу половину — жодного ЗАЙВОГО стріму на сторінці.
    def subscribed_streams_for(who)
      get "/alerts",
          headers: { "Authorization" => "Bearer #{who.generate_token_for(:api_access)}", "Accept" => "text/html" }
      response.body.scan(/signed-stream-name="([^"]+)"/).flatten
              .map { |name| Turbo::StreamsChannel.verified_stream_name(name) }
    end

    it "subscribes each viewer to their OWN organization alert stream" do
      stranger = create(:user, :forester, organization: other_organization)

      expect(subscribed_streams_for(user))
        .to eq([ "ews_alerts_org_#{organization.id}_e#{organization.stream_epoch}" ])
      expect(subscribed_streams_for(stranger))
        .to eq([ "ews_alerts_org_#{other_organization.id}_e#{other_organization.stream_epoch}" ])
    end
  end

  context "with turbo_stream format" do
    # [TEST.10] Приклад приймав `{200, 406, 500}` під підставою «Phlex може не
    # дорендеритись», тобто не міг сказати навіть того, чи відповідь взагалі
    # Turbo-стрім. А несуче тут саме ЦІЛЬ: доти контролер писав рукописний
    # `alert_#{id}`, якого не існувало ні на одній сторінці, і `replace` був
    # тихим no-op — тож пін мусить тримати `target`, а не факт виклику.
    it "replaces the alert row in place with its resolved state" do
      patch resolve_alert_path(own_alert),
            headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(action="replace"))
      expect(response.body).to include(%(target="ews_alert_#{own_alert.id}"))
      expect(response.body).to include("✓ Resolved")
      expect(response.body).not_to include("Acknowledge & Resolve")
    end

    # [ARCH.31] Замінений рядок стоїть у РЕЄСТРІ, тож мусить донести туди й
    # контекст: без `linked:` підтверджена тривога мовчки втрачала б єдиний вхід
    # на власну SOP-сторінку — саме там, де оператор щойно діяв, і саме тоді,
    # коли runbook потрібен. Дефолт компонента fail-closed, тож пропущений kwarg
    # тут не падає, а тихо звужує — його ловить рівно цей рядок.
    it "замінений рядок ЗБЕРІГАЄ вхід на сторінку тривоги" do
      patch resolve_alert_path(own_alert),
            headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")

      expect(response.body).to include("href=\"/alerts/#{own_alert.id}\"")
    end
  end
end

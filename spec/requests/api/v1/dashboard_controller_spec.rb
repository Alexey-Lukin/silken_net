# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::DashboardController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:cluster) { create(:cluster, organization: organization) }

  # [ARCH.119] Нога The Graph оголошено ЖИВА для всього файлу. Без цього activation-гейт
  # короткозамикає ДО інстанціювання сервісу, тож `allow_any_instance_of` не досягається
  # ніколи — і приклади нижче, включно з «The Graph лежить», мовчки доводили б гейт
  # замість того, що названо в їхніх `it`. Сам гейт має власний контекст у кінці файлу.
  before { allow(TheGraph::QueryService).to receive(:configured?).and_return(true) }

  describe "GET /dashboard" do
    context "when as JSON" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_total_carbon_minted).and_return(0)
      end

      it "returns dashboard stats" do
        get "/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body).to have_key("trees")
        expect(body).to have_key("economy")
        expect(body).to have_key("security")
        expect(body).to have_key("energy")
        expect(body).to have_key("global_onchain_carbon")
      end

      it "returns correct tree stats" do
        tree = create(:tree, cluster: cluster, status: :active)
        create(:telemetry_log, tree: tree, voltage_mv: 4200, created_at: 30.minutes.ago)

        get "/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        trees = response.parsed_body["trees"]
        expect(trees["total"]).to be >= 1
        expect(trees["active"]).to be >= 1
      end

      it "returns economy stats with wallet balance" do
        tree = create(:tree, cluster: cluster)
        create(:wallet, tree: tree, balance: 100.0)

        get "/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        economy = response.parsed_body["economy"]
        expect(economy["total_scc"]).to be_a(Numeric)
      end

      it "returns security stats" do
        tree = create(:tree, cluster: cluster)
        create(:ews_alert, cluster: cluster, tree: tree, status: :active)

        get "/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        security = response.parsed_body["security"]
        expect(security["active_alerts"]).to be >= 1
      end

      it "returns energy stats" do
        get "/dashboard", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        energy = response.parsed_body["energy"]
        expect(energy).to have_key("avg_voltage")
        # [ARCH.84/ARCH.99] `status` знято: вердикт про запас енергії на шині,
        # яку BQ25570 сам і стабілізує, був фабрикацією за конструкцією.
        expect(energy).not_to have_key("status")
      end
    end

    context "when as HTML" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_total_carbon_minted).and_return(0)
      end

      it "renders the dashboard page" do
        get "/dashboard", headers: headers
        expect(response).to have_http_status(:ok)
      end

      # [UI.5] Роле-фільтр меню живе в компоненті, а ПРОВОДКА актора — у
      # `DashboardLayout`. Компонентна спека другої половини не бачить у принципі
      # (вона конструює сайдбар повз layout), тож забутий kwarg лишив би її зеленою
      # при повністю відкритому меню. Позитивна половина обовʼязкова: без неї
      # приклад проходив би й на порожній сторінці, тобто не доводив би нічого.
      it "ховає від subscriber пункти меню, закриті рольовим гардом" do
        subscriber = create(:user, :subscriber, organization: organization)

        get "/dashboard",
            headers: { "Authorization" => "Bearer #{subscriber.generate_token_for(:api_access)}" }

        expect(response.body).to include(%(href="#{wallets_path}"))
        expect(response.body).not_to include(%(href="#{settings_path}"))
        expect(response.body).not_to include(%(href="#{audit_logs_path}"))
        expect(response.body).not_to include(%(href="#{organizations_path}"))
      end

      # 🔴 Дзеркальна половина, без якої пін вище НЕ стереже проводку: дефолт
      # fail-closed, тож забутий `current_user:` у layout ховає гейтоване від УСІХ —
      # і негативний приклад лишається зеленим. Забуту проводку ловить лише
      # позитивне твердження про роль, якій пункт належить.
      it "показує admin пункти, закриті для нижчих ролей" do
        admin = create(:user, :admin, organization: organization)

        get "/dashboard",
            headers: { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" }

        expect(response.body).to include(%(href="#{settings_path}"))
        expect(response.body).to include(%(href="#{audit_logs_path}"))
      end

      # Геопросторова матриця віддає координати й DID живого флоту. Рядок, що
      # вирішує ЧИЙ це флот, живе в контролері — компонентна спека його не
      # бачить (там організація приходить моком). Без цього піна підміна на
      # `Organization.first` лишила б усю сюїту зеленою, а крос-тенант — живим.
      def subscribed_streams_for(who)
        get "/dashboard",
            headers: { "Authorization" => "Bearer #{who.generate_token_for(:api_access)}" }
        response.body.scan(/signed-stream-name="([^"]+)"/).flatten
                .map { |s| Turbo::StreamsChannel.verified_stream_name(s) }
      end

      # ⚠️ Двоє юзерів обовʼязкові: `organization` створюється в цьому файлі
      # першою, тож `Organization.first` їй ДОРІВНЮЄ — з одним прикладом
      # мутація на неї лишається зеленою. Ловить лише різниця відповідей.
      # [UI.4] Очікуваний набір ЦІЛОЇ сторінки, не одного компонента: `Dashboard::Home`
      # підписується на три домени своєї стрічки, `Dashboard::Map` — на четвертий.
      # Порядок = порядок рендеру.
      def expected_streams_for(org)
        %w[ews_alerts blockchain_ledger maintenance_records geospatial_matrix]
          .map { |prefix| "#{prefix}_org_#{org.id}_e#{org.stream_epoch}" }
      end

      it "subscribes each viewer to their OWN organization map stream" do
        other_organization = create(:organization)
        stranger = create(:user, organization: other_organization)

        expect(subscribed_streams_for(user)).to eq(expected_streams_for(organization))
        expect(subscribed_streams_for(stranger)).to eq(expected_streams_for(other_organization))
      end

      # 🔴 [UI.4] Рівність МНОЖИНИ, а не `include` — бо дефект цього сайту виглядає
      # як ЗАЙВИЙ стрім, і `include` його не бачить за побудовою. Кожен зайвий домен
      # у `Dashboard::Home::FEED_DOMAINS` коштує повний GET сторінки кожному глядачеві
      # на кожну чужу подію; кожен відсутній — мовчазно застарілу стрічку.
      #
      # ⚠️ Що цей пін НЕ доводить, і це треба тримати в голові: він стереже
      # відповідність набору ЦЬОМУ списку, а не складу `fetch_recent_events`. Дрейф
      # між ними лишається людською відповідальністю — сигнал у домен, якого стрічка
      # більше не показує, тут зелений. Статичного гейта на цю вісь немає: склад
      # стрічки — рантайм-масив із трьох ORM-ланцюгів, і жоден екстрактор не виводить
      # із нього символ домену.
      it "subscribes to exactly the domains its event feed is built from" do
        expect(subscribed_streams_for(user)).to eq(expected_streams_for(organization))

        expect(Dashboard::Home::FEED_DOMAINS).to eq(%i[alerts ledger maintenance])
      end

      it "renders map nodes only for the viewer's own geolocated trees" do
        other_organization = create(:organization)
        other_cluster = create(:cluster, organization: other_organization)
        own = create(:tree, cluster: cluster, latitude: 49.44, longitude: 32.06)
        foreign = create(:tree, cluster: other_cluster, latitude: 50.45, longitude: 30.52)
        ungeolocated = create(:tree, cluster: cluster, latitude: nil, longitude: nil)

        get "/dashboard", headers: headers

        expect(response.body).to include("map_node_#{own.id}")
        expect(response.body).not_to include("map_node_#{foreign.id}")
        expect(response.body).not_to include("map_node_#{ungeolocated.id}")
        expect(response.body).not_to include(foreign.did)
      end

      # 🔴 [UI.4] Проводку підстави доводить ЛИШЕ request-рівень: компонентна спека
      # рендерить повз маршрутизатор і повз викликача, тож вона однаково зелена й
      # тоді, коли контролер ціле взагалі не рахує (`04_06 §B.2` BP #14).
      # Стелю ріжемо `stub_const`, бо інакше приклад вимагав би 501 дерева.
      it "declares that the map shows only part of the fleet when the ceiling truncates it" do
        # ⚠️ Три ОКРЕМІ виклики, не цикл: `Tree` створює гаманець колбеком, а
        # Prosopite групує за бектрейсом — тож `3.times { create(:tree) }` читається
        # як N+1 ФІКСТУРИ й валить приклад про запит. Глушити детектор тут не можна:
        # саме він і є носієм сусідньої осі (PERF.1).
        create(:tree, cluster: cluster, latitude: 49.40, longitude: 32.06)
        create(:tree, cluster: cluster, latitude: 49.41, longitude: 32.06)
        create(:tree, cluster: cluster, latitude: 49.42, longitude: 32.06)
        stub_const("#{described_class}::MAP_NODE_LIMIT", 2)

        get "/dashboard", headers: headers

        # Ліхтар на передумову: дерев справді БІЛЬШЕ за стелю — інакше приклад
        # доводив би лише те, що зрізати не було чого.
        expect(organization.clusters.joins(:trees).count).to be_positive
        expect(response.body).to include(I18n.t("ui.measurement.coverage", measured: 2, total: 3))
      end

      it "stays silent about coverage when the whole fleet fits under the ceiling" do
        create(:tree, cluster: cluster, latitude: 49.40, longitude: 32.06)
        create(:tree, cluster: cluster, latitude: 49.41, longitude: 32.06)

        get "/dashboard", headers: headers

        expect(response.body).to include("Live Active Nodes: 2")
        expect(response.body).not_to include(I18n.t("ui.measurement.coverage", measured: 2, total: 2))
      end
    end

    context "with global_onchain_carbon from The Graph" do
      it "returns the minted amount from The Graph" do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_total_carbon_minted).and_return(1_450_000)

        get "/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["global_onchain_carbon"]).to eq(1_450_000)
      end

      # 🔴 [ARCH.103] Доти цей приклад ВИМАГАВ фабрикації, і казав це у власній
      # назві («falls back to 0»): недоступний subgraph друкувався як «протокол
      # намінтував нуль» — найспокійніший можливий стан, невідрізнимий від справжнього.
      it "reports the platform figure as unmeasured when The Graph service raises an error" do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_total_carbon_minted)
          .and_raise(TheGraph::QueryService::QueryError, "The Graph node is syncing")

        get "/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("global_onchain_carbon")
        expect(response.parsed_body["global_onchain_carbon"]).to be_nil
      end

      # [ARCH.119] Сусід приклада вище на ІНШІЙ осі: там нога жива й ВІДМОВИЛА, тут її
      # не заведено взагалі. Назовні обидва дають «не виміряно» — і саме тому вони мусять
      # розрізнятись у ЛОГАХ, інакше оператор не знає, чи чекати на вендора, чи заводити
      # ключ. ⚠️ Пін на `not_to receive(:new)` несе другу половину: гейт стоїть ДО
      # інстанціювання, тож марного винятку на кожен запит більше немає.
      it "reports the figure as unmeasured and NAMES the unconfigured leg when the subgraph has no URL" do
        allow(TheGraph::QueryService).to receive(:configured?).and_return(false)
        allow(TheGraph::QueryService).to receive(:new)
        allow(Rails.logger).to receive(:warn)

        get "/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["global_onchain_carbon"]).to be_nil
        expect(TheGraph::QueryService).not_to have_received(:new)
        expect(Rails.logger).to have_received(:warn).with(/не сконфігуровано/)
      end
    end

    it "returns 401 without authentication" do
      get "/dashboard", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # 🔴 [ARCH.84/ARCH.99] Обидва приклади тут ЦЕМЕНТУВАЛИ фабрикацію: вимагали
    # вердикту «STABLE/LOW_RESERVE» від величини, яка про запас енергії не каже
    # нічого ЗА КОНСТРУКЦІЄЮ — `latest_voltage_mv` це мВ VDDA, а BQ25570
    # стабілізує цю шину на 3.3 В, тобто поріг «> 3300» порівнював величину з її
    # ж регульованим номіналом. Шкалу заряду знято присудом founder ще при
    # ARCH.99; цей ключ пережив ту хвилю, бо мав НУЛЬ споживачів.
    #
    # ⚠️ Найгірший був перший: він вимагав «LOW_RESERVE» на ПОРОЖНІЙ базі, тобто
    # цементував вердикт про запас енергії там, де телеметрії немає взагалі.
    context "with the energy diagnostic" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_total_carbon_minted).and_return(0)
      end

      it "не віддає вердикту про запас енергії — його нічим виміряти" do
        get "/dashboard", headers: headers, as: :json

        energy = response.parsed_body["energy"]
        expect(energy).not_to have_key("status")
        expect(energy.keys).to contain_exactly("avg_voltage")
      end

      # [ARCH.84] Назва цього приклада доти сама цементувала дефект — «на порожній
      # базі воно НУЛЬ». Нуль на шині VDDA не нейтральний: це БРАУНАУТ, тобто
      # найгірший можливий вимір, підставлений замість відсутності виміру, і
      # друкувався він на ГОЛОВНІЙ сторінці. `AVG` мовчки пропускає NULL, тож
      # порожній набір мусить лишатись `null`.
      it "лишає сире діагностичне число, а на порожній базі віддає null — не браунаут" do
        get "/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("energy", "avg_voltage")).to be_nil
      end

      # ⊥ Ліхтар: число справді рахується, а не заглушене нулем назавжди.
      it "віддає середнє по активних деревах, коли телеметрія є" do
        create(:tree, cluster: cluster, status: :active, latest_voltage_mv: 4100)

        get "/dashboard", headers: headers, as: :json

        expect(response.parsed_body.dig("energy", "avg_voltage")).to be > 3300
      end
    end
  end

  # [UI.8] Проводка, а не компонент: аватар живе в `DashboardLayout`, тож
  # компонентна спека його не бачить ЗА ПОБУДОВОЮ (вона рендерить повз layout).
  # Пін позитивний навмисно — саме він падає, якщо лінк знімуть: `Users::Profile`
  # був повністю побудований і недосяжний, бо `users_me_path` не згадувався ніде.
  describe "profile door in the top bar" do
    it "renders the avatar as a link to the own-profile page" do
      get "/dashboard", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/users/me"))
    end
  end
end

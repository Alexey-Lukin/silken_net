# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ContractsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  let!(:own_contract) do
    create(:naas_contract, organization: organization, cluster: own_cluster)
  end
  let!(:other_contract) do
    create(:naas_contract, organization: other_organization, cluster: other_cluster)
  end

  # [TEST.12] Тут стояло пʼять `define_method`-гардів із прозою «methods not yet on the model»
  # і «scopes that don't exist». Виміряно рантаймом — проза застаріла: `current_yield_performance`,
  # `BlockchainTransaction.confirmed` і `EwsAlert.active` існують, тож
  # ті гарди були інертні; пʼятий (`NaasContract#blockchain_transactions`) справді дописував
  # асоціацію, якої на моделі немає, — але її не кличе НІХТО (ні `app/`, ні ця спека), тобто
  # це залишок від прибраного колись виклику. Знято всі пʼять: підміна API моделі в `before`
  # переживає рефакторинг мовчки й робить майбутній дрейф неперевірним.

  describe "GET /contracts" do
    # [ARCH.103] ⚖️ Кластерна семантика. Пін на РІВНІ ЗАПИТУ навмисно: компонентна
    # спека сторінки подає `total_minted` фікстурою-числом, тож вона рендерила значення,
    # якого контролер ніколи не виробляв — і саме тому «0.0 SCC» під підписом «Нараховано
    # SCC» (це `nil.to_f`) прожило непоміченим. Мок вигадав шкалу; побачити це можна лише
    # ходом крізь маршрутизатор.
    context "when the page reports cluster emission (ARCH.103)" do
      let(:tree) { create(:tree, cluster: own_cluster) }
      let(:wallet) { tree.wallet || create(:wallet, tree: tree) }

      # 🔴 Дискримінатор семантики: ДВА контракти на ОДНОМУ кластері. Сума «по
      # контрактах» дала б 240 — рівно та переоцінка в N разів, через яку контрактну
      # деривацію й визнано невиконуваною. Кластерна множина дедуплікована, тож 120.
      it "рахує емісію кластера ОДИН раз, скільки б контрактів на ньому не висіло" do
        create(:naas_contract, organization: organization, cluster: own_cluster)
        create(:blockchain_transaction, wallet: wallet, amount: 120,
                                        token_type: :carbon_coin, status: :confirmed)

        get "/contracts", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("120.0 SCC")
        expect(response.body).not_to include("240.0 SCC")
      end

      # ⊥ Ліхтар на протилежне плече: спалення ВІДНІМАЄТЬСЯ. Без нього пін проходив би
      # і на голій сумі мінтів, тобто не доводив би, що ми беремо саме ЧИСТУ емісію.
      it "віднімає спалення, а не сумує його як емісію" do
        create(:blockchain_transaction, wallet: wallet, amount: 120,
                                        token_type: :carbon_coin, status: :confirmed)
        create(:blockchain_transaction, wallet: wallet, amount: 20, token_type: :carbon_coin,
                                        status: :confirmed, sourceable: own_contract, direction: :burn)

        get "/contracts", headers: headers

        expect(response.body).to include("100.0 SCC")
      end

      # [ARCH.103 ⚖️ 08-20] Відʼємна чиста емісія друкується ЗІ ЗНАКОМ, не клампиться.
      # 🔴 Числа картки й рядка СВІДОМО різні (-70 ⊥ -100): перша редакція тримала
      # одне значення в обох вузлах, і клампнута картка ховалась за здоровою коміркою
      # рядка — мутація clamp'а лишалась зеленою (пін через сусідній вузол).
      it "друкує відʼємну чисту емісію зі знаком у КАРТЦІ й у РЯДКУ, не клампить" do
        create(:blockchain_transaction, wallet: wallet, amount: 20,
                                        token_type: :carbon_coin, status: :confirmed)
        create(:blockchain_transaction, wallet: wallet, amount: 120, token_type: :carbon_coin,
                                        status: :confirmed, sourceable: own_contract, direction: :burn)
        second_cluster = create(:cluster, organization: organization)
        second_tree = create(:tree, cluster: second_cluster)
        create(:naas_contract, organization: organization, cluster: second_cluster)
        create(:blockchain_transaction, wallet: second_tree.wallet, amount: 30,
                                        token_type: :carbon_coin, status: :confirmed)

        get "/contracts", headers: headers

        expect(response.body).to include("-70.0 SCC")   # картка: (-100) + 30
        expect(response.body).to include("-100.0 SCC")  # комірка рядка own_cluster
      end
    end

    context "when as JSON" do
      it "returns only contracts belonging to the user's organization" do
        get "/contracts", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ids = response.parsed_body["data"].map { |c| c["id"] }
        expect(ids).to include(own_contract.id)
        expect(ids).not_to include(other_contract.id)
      end

      # [ARCH.103] JSON-дзеркало HTML-комірки: рядок несе КЛАСТЕРНУ чисту емісію, а
      # мертва колонка не їде назовні. Пін на значення несе ОБИДВА плеча (120 − 20),
      # інакше він зелений і на голій сумі мінтів.
      it "reports the cluster's net emission per row instead of the dead column" do
        tree = create(:tree, cluster: own_cluster)
        wallet = tree.wallet || create(:wallet, tree: tree)
        create(:blockchain_transaction, wallet: wallet, amount: 120,
                                        token_type: :carbon_coin, status: :confirmed)
        create(:blockchain_transaction, wallet: wallet, amount: 20, token_type: :carbon_coin,
                                        status: :confirmed, sourceable: own_contract, direction: :burn)

        get "/contracts", headers: headers, as: :json

        row = response.parsed_body["data"].find { |c| c["id"] == own_contract.id }
        expect(row["cluster_emission"]).to eq(100.0)
        expect(row).not_to have_key("emitted_tokens")
        # `total_funding`, не alias: `as_json(only:)` мовчки ігнорує alias-атрибути,
        # тож `:total_value` у старому списку не віддавав нічого (виміряно).
        expect(row).to include("total_funding")
      end

      it "returns empty data when user has no contracts" do
        fresh_org = create(:organization)
        fresh_user = create(:user, organization: fresh_org)
        fresh_token = fresh_user.generate_token_for(:api_access)
        fresh_headers = { "Authorization" => "Bearer #{fresh_token}" }

        get "/contracts", headers: fresh_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]).to be_empty
      end

      it "scopes admin to own-org contracts (org-scoped, not platform)" do
        get "/contracts", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)

        ids = response.parsed_body["data"].map { |c| c["id"] }
        expect(ids).to include(own_contract.id)
        expect(ids).not_to include(other_contract.id)
      end
    end

    context "when as HTML" do
      # 🔴 Цей блок ІСНУВАВ і був зелений увесь час, поки картка «Network Health»
      # рендерила голе «%»: він перевіряв лише код 200, а зламаний `@stats[:avg_health]`
      # нічого не кидав — nil тихо інтерполювався в порожнечу. Тобто дві половини
      # контракту тут зустрічались, і НІХТО їх не порівнював ([UI.7], BP #14).
      it "renders the dashboard page" do
        get "/contracts", headers: headers
        expect(response).to have_http_status(:ok)
      end

      # ⚠️ `health_index` мусить бути ЯВНО ненульовим: фабрика лишає колонку NULL,
      # а `AVG(NULL)` = NULL, тож без цього не-nil гілка агрегації не бралась ніколи
      # — happy-path картки не проходив наскрізь у жодному прикладі.
      it "renders the portfolio average as a percentage, not the raw 0..1 index" do
        own_cluster.update!(health_index: 0.873)

        get "/contracts", headers: headers.merge("Accept" => "text/html")

        expect(response.body).to include("87.3%")
      end

      # 🔴 [ARCH.84] Пін на ЗВАЖУВАННЯ. Доти середнє рахувалось по РЯДКАХ контрактів
      # (`joins(:cluster).average`), тож кластер важив стільки, скільки на нього
      # випадково підписано паперів. Присуд дав власний підпис картки — «Avg Cluster
      # Health», — тож множина мусить бути КЛАСТЕРНОЮ.
      #
      # ⚠️ Фікстура навмисно асиметрична: здоровий кластер з ОДНИМ контрактом проти
      # мертвого з ТРЬОМА. Симетрична дала б однакове число обома формами й нічого
      # не доводила б.
      it "weights the portfolio average per CLUSTER, not per contract row" do
        healthy = own_cluster
        healthy.update!(health_index: 1.0)
        sick = create(:cluster, organization: organization)
        sick.update!(health_index: 0.0)

        create(:naas_contract, organization: organization, cluster: healthy, status: :active)
        3.times { create(:naas_contract, organization: organization, cluster: sick, status: :active) }

        get "/contracts", headers: headers.merge("Accept" => "text/html")

        expect(response.body).to include("50.0%")   # (1.0 + 0.0) / 2 кластери
        expect(response.body).not_to include("25.0%") # (1+0+0+0) / 4 рядки контрактів
      end

      # 🔴 [ARCH.84] Цей приклад РАТИФІКУВАВ дефект прозою, і його стара редакція була
      # найсильнішим внутрішнім аргументом ПРОТИ фіксу: «Картка мусить читатись як
      # „повне здоров'я", не як „0%"», плюс `include("100.0%")` на request-рівні.
      #
      # Він мав рацію в половині: «0%» тут справді брехня (це вимір, і то найгірший).
      # Помилка — у припущенні, що альтернатива одна. Порожній скоуп означає, що
      # міряти НЕМА ЧОГО, і чесна відповідь третя: ні 0%, ні 100%.
      it "shows «not measured» for an organization with no contracts — neither 0% nor a fabricated 100%" do
        fresh_user = create(:user, organization: create(:organization))

        get "/contracts",
            headers: { "Authorization" => "Bearer #{fresh_user.generate_token_for(:api_access)}",
                       "Accept" => "text/html" }

        expect(response.body).to include(I18n.t("ui.measurement.not_measured"))
        expect(response.body).not_to include("100.0%")
        expect(response.body).not_to include("0.0%")
      end
    end

    it "returns 401 without authentication" do
      get "/contracts", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /contracts/:id" do
    context "when as JSON" do
      it "returns a contract belonging to the user's organization" do
        get "/contracts/#{own_contract.id}", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["contract"]["id"]).to eq(own_contract.id)
      end

      it "returns 404 for a contract from another organization" do
        get "/contracts/#{other_contract.id}", headers: headers, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "denies admin a contract from another org (org-scoped, not platform)" do
        get "/contracts/#{other_contract.id}", headers: admin_headers, as: :json
        expect(response).to have_http_status(:not_found)
      end

      # [ARCH.103] Дзеркало HTML-героя: `cluster_emission` — окремий ключ верхнього
      # рівня (величина належить кластеру, не контракту), а `contract` — явний
      # `only:` замість голого дампу, тож мертва колонка не їде назовні й майбутня
      # колонка не публікується автоматично. Пін значення = обидва плеча формули.
      it "reports the hero's cluster emission and stops dumping the dead column" do
        tree = create(:tree, cluster: own_cluster)
        wallet = tree.wallet || create(:wallet, tree: tree)
        create(:blockchain_transaction, wallet: wallet, amount: 120,
                                        token_type: :carbon_coin, status: :confirmed)
        create(:blockchain_transaction, wallet: wallet, amount: 20, token_type: :carbon_coin,
                                        status: :confirmed, sourceable: own_contract, direction: :burn)

        get "/contracts/#{own_contract.id}", headers: headers, as: :json

        expect(response.parsed_body["cluster_emission"]).to eq(100.0)
        expect(response.parsed_body["contract"]).to include("total_funding", "status")
        expect(response.parsed_body["contract"]).not_to have_key("emitted_tokens")
      end

      # [ARCH.103 ⚖️ 08-20 «чесний мінус»] Чиста емісія буває відʼємною (спалення >
      # мінт); знак їде на дріт і на екран ЯК Є — клампи в цьому репо вже двічі
      # маскували симптоми (`calculate_damage_ratio`, `slashUpTo`).
      it "reports a NEGATIVE cluster emission honestly when burns exceed mints" do
        tree = create(:tree, cluster: own_cluster)
        wallet = tree.wallet || create(:wallet, tree: tree)
        create(:blockchain_transaction, wallet: wallet, amount: 20,
                                        token_type: :carbon_coin, status: :confirmed)
        create(:blockchain_transaction, wallet: wallet, amount: 120, token_type: :carbon_coin,
                                        status: :confirmed, sourceable: own_contract, direction: :burn)

        get "/contracts/#{own_contract.id}", headers: headers, as: :json

        expect(response.parsed_body["cluster_emission"]).to eq(-100.0)
      end

      # [ARCH.103 ⚖️ 08-20] Леджер героя = ТОЙ САМИЙ дім, що герой (`for_cluster`):
      # слеш «останнього дерева» (wallet: nil, cluster) ВИДИМИЙ, чужий кластер тієї
      # самої організації — ні. Обидва боки СВОЇ: чужу організацію відсіює
      # тенант-скоуп find_contract, не рескоуп (BP 21).
      it "scopes the emission ledger to the hero's cluster, orphan slash rows included" do
        orphan_slash = create(:blockchain_transaction, wallet: nil, cluster: own_cluster,
                                                       amount: 5, token_type: :carbon_coin,
                                                       status: :confirmed, sourceable: own_contract, direction: :burn)
        other_cluster = create(:cluster, organization: organization)
        other_tree = create(:tree, cluster: other_cluster)
        foreign_row = create(:blockchain_transaction, wallet: other_tree.wallet, amount: 7,
                                                      token_type: :carbon_coin, status: :confirmed)

        get "/contracts/#{own_contract.id}", headers: headers, as: :json

        ids = response.parsed_body["emission_history"].map { |row| row["id"] }
        expect(ids).to include(orphan_slash.id)
        expect(ids).not_to include(foreign_row.id)
      end

      # [UI.8] Пін на ЗМІСТ, а не на присутність ключа: `backing_asset` є JSON-дзеркалом
      # живої панелі `Contracts::Show#render_backing_asset_panel`, і саме поле загрози
      # роками розходилось із нею порогом (JSON — будь-яка severity, панель — лише
      # critical). `have_key` цього не бачив і не міг: він зелений на будь-якому вмісті.
      it "mirrors the backing-asset panel, threat threshold included" do
        create(:ews_alert, cluster: own_contract.cluster, severity: :medium, status: :active)

        get "/contracts/#{own_contract.id}", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        backing = response.parsed_body.fetch("backing_asset")
        # Панель питає `Cluster#active_threats?` = unresolved.critical — тож
        # НЕрозвʼязана MEDIUM-тривога не сміє засвітити «загрозу».
        expect(backing["active_threats"]).to be(false)
      end

      it "reports a threat when the cluster has an unresolved CRITICAL alert" do
        create(:ews_alert, cluster: own_contract.cluster, severity: :critical, status: :active)

        get "/contracts/#{own_contract.id}", headers: headers, as: :json

        expect(response.parsed_body.fetch("backing_asset")["active_threats"]).to be(true)
      end
    end

    context "when as HTML" do
      # 🔴 [TEST.12 вісь D, друга група присуду D3] Сторінка несе `@contract` із
      # контролера. Пін на назву кластера, а не на id: id є ще й у самому URL, тож
      # він рендерився б і при геть іншому записі — а сектор приходить рівно з
      # переданого контракту через його асоціацію.
      it "друкує ЗАПИТАНИЙ контракт, а не порожню сторінку" do
        get "/contracts/#{own_contract.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(own_cluster.name.upcase)
      end
    end

    it "returns 401 without authentication" do
      get "/contracts/#{own_contract.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /contracts/stats" do
    it "returns financial analytics for the user's organization" do
      allow(PriceOracleService).to receive(:current_scc_price).and_return(25.5)

      get "/contracts/stats", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body).to have_key("total_contracted")
      expect(body).to have_key("cluster_health")

      # 🔴 [ARCH.103] Доти обидва ключі стерегли лише `have_key` — тобто НАЯВНІСТЬ,
      # ніколи значення, — і саме тому фабрикація прожила стільки: `total_tokens_minted`
      # сумував колонку без жодного писача, а `attested_value_usd` множив ту суму на
      # живу ціну з оракула, тобто був доларовою оцінкою портфеля, структурно рівною
      # нулю. Єдиний правдивий множник у виразі створював враження обчислення.
      #
      # ✅ ⚖️ Присуд founder (кластерна семантика) зняв ПЕРШУ половину: величина знову
      # вимірювана, тож пін перецілено з «не виміряно» на САМЕ ЗНАЧЕННЯ — інакше він
      # стеріг би стан, якого вже немає. Дискримінатор до цього нуля (він пройшов би й
      # на захардкодженому) стоїть у `GET /contracts` вище.
      # ⛔ `attested_value_usd` лишається `nil` СВІДОМО: він потребує зовнішнього
      # цінового оракула на списковому ендпоінті, і рішення про той виклик — окреме.
      expect(body["total_tokens_minted"]).to eq(0.0)
      expect(body["attested_value_usd"]).to be_nil
    end

    # ⚠️ Пара до піна вище: оракул більше не смикають узагалі. Без цього прикладу
    # «полагодити» відсутню оцінку можна було б, лишивши зовнішній виклик заради
    # множення на невідоме — витрата без результату, чия тиша ще й читалась би як
    # «оцінка не працює», ховаючи справжню причину.
    it "does not call the price oracle while the minted amount is unmeasured" do
      allow(PriceOracleService).to receive(:current_scc_price)

      get "/contracts/stats", headers: headers, as: :json

      expect(PriceOracleService).not_to have_received(:current_scc_price)
      expect(response).to have_http_status(:ok)
    end

    # [SEC.25 Ф2] Доти цей екшен мав ВЛАСНУ відповідь на «нема організації» (403 через
    # ручний гард), тоді як сусідні сторінки того самого дашборду відповідали 500, або
    # 422, або 200 із порожнім станом. Тепер шлях один: 422 + машинний код.
    it "returns 422 with a machine-readable code when the user has no organization" do
      user_without_org = create(:user, organization: nil)
      token = user_without_org.generate_token_for(:api_access)
      no_org_headers = { "Authorization" => "Bearer #{token}" }

      get "/contracts/stats", headers: no_org_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("no_organization")
    end

    it "returns 401 without authentication" do
      get "/contracts/stats", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "when organization has no clusters" do
      # [ARCH.84] Доти: «returns cluster_health as 1.0». Клієнтський контракт
      # (`00_04`) лишає шкалу 0..1, але поле стало **nullable**, і покриття їде
      # поруч — саме воно розводить «нема чого міряти» від «не змогли».
      it "returns cluster_health as null with an honest zero coverage" do
        allow(PriceOracleService).to receive(:current_scc_price).and_return(25.5)

        fresh_org = create(:organization)
        fresh_user = create(:user, organization: fresh_org)
        fresh_headers = { "Authorization" => "Bearer #{fresh_user.generate_token_for(:api_access)}" }

        get "/contracts/stats", headers: fresh_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("cluster_health")
        expect(response.parsed_body["cluster_health"]).to be_nil
        expect(response.parsed_body["clusters_total"]).to eq(0)
      end
    end

    # 🔴 [ARCH.84] Доти цей контекст звався «returns 1.0 as fallback» і пінив, що
    # БУДЬ-ЯКИЙ виняток усередині розрахунку віддає «ідеальне здоров'я». Голого
    # `rescue` більше немає: аварія мусить читатись як аварія, а не як бездоганний ліс.
    context "when the health calculation blows up" do
      it "surfaces the failure instead of laundering it into perfect health" do
        allow(PriceOracleService).to receive(:current_scc_price).and_return(25.5)
        allow(Cluster).to receive(:health_coverage).and_raise(ActiveRecord::StatementInvalid, "DB error")

        get "/contracts/stats", headers: headers, as: :json

        expect(response).not_to have_http_status(:ok)
        expect(response.parsed_body["cluster_health"]).to be_nil
      end
    end
  end
end

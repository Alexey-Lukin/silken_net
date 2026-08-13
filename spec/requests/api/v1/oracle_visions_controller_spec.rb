# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OracleVisionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:forester_token) { forester.generate_token_for(:api_access) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:forester_headers) { { "Authorization" => "Bearer #{forester_token}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

  let!(:cluster) { create(:cluster, organization: organization) }

  describe "GET /oracle_visions" do
    before do
      Rails.cache.clear
      allow(Rails.cache).to receive(:fetch).and_call_original
      # [TENANT-ISOLATION]: Cache key was promoted from a global
      # "oracle_expected_yield_24h" to a per-org "oracle_expected_yield_24h_org_<id>"
      # to stop cross-tenant leakage. Match the org-scoped key so the stub fires
      # for the forester/admin tests below.
      # [ARCH.84] Форма кешованого значення — ХЕШ скалярів (`value`/`measured`/`total`),
      # бо прогноз рахується лише по деревах із виміряним стресом і мусить нести
      # покриття. Стаб мусить дзеркалити форму, інакше він тестує неіснуючий контракт.
      allow(Rails.cache).to receive(:fetch)
        .with("oracle_expected_yield_24h_org_#{organization.id}", anything)
        .and_return({ value: 1.5, measured: 1, total: 1 })
    end

    context "when as JSON" do
      it "returns visions and emission forecast for forester" do
        get "/oracle_visions", headers: forester_headers, as: :json
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body).to have_key("visions")
        expect(body).to have_key("emission_forecast")
      end

      it "returns visions for admin (who is also a forest_commander)" do
        get "/oracle_visions", headers: admin_headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "when as HTML" do
      # 🔴 [TEST.12 вісь D + ARCH.89] Цей приклад НАВМИСНО обходить стаб кешу з
      # `before` — і саме стаб ховав живий дефект: він віддавав Float, тоді як
      # справжній розрахунок після першого ж дерева дає **BigDecimal** (`sap_flow` —
      # `decimal`), а Phlex тоді не вмів друкувати BigDecimal узагалі. Показник
      # «Expected Yield» рендериться голим блоком, тож на будь-якій організації з
      # телеметрією він зникав з екрана, а сюїта лишалась зеленою: у фікстурі дерев
      # не було, і число приходило зі стабу вже правильним типом. ⚠️ Корінь знято
      # (`ApplicationComponent#format_object`), але приклад лишається: він стереже
      # ТИП на тракті, де фікстура взагалі не бере участі — а це вісь ПРОВЕНАНСУ.
      # ⚠️ Пін цілиться у ВУЗОЛ (`>…<`), а не в документ: голе `include("1.5")`
      # вакуумне за побудовою — Tailwind сипле в розмітку класи на кшталт `gap-1.5`.
      it "друкує ОБЧИСЛЕНИЙ прогноз, а не порожній вузол" do
        RSpec::Mocks.space.proxy_for(Rails.cache).reset
        tree = create(:tree, cluster: cluster)
        create(:telemetry_log, tree: tree, sap_flow: 2.5)

        get "/oracle_visions", headers: forester_headers

        expect(response).to have_http_status(:ok)
        yield_node = response.body[/drop-shadow-\[0_0_8px_rgba\(52,211,153,0\.5\)\]"[^>]*>\s*([^<]*)</, 1]
        expect(yield_node.to_s.strip).to match(/\A\d+(\.\d+)?\z/)
      end
    end

    it "returns 403 for investor users" do
      get "/oracle_visions", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/oracle_visions", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # 🔴 [ARCH.84] Цей контекст роками НЕ прогонив розрахунку, попри власну назву:
    # файловий `before` вище стабить `Rails.cache.fetch` для org-ключа, а вкладений
    # `Rails.cache.clear` стаб не знімає — тіло `calculate_expected_yield` не
    # виконувалось ЖОДНОГО разу, і обидва приклади вітали підставлені 1.5, чесно
    # бачачи `Numeric`. Тепер стаб знімається явно, і приклади пінять ЗНАЧЕННЯ.
    context "when calculate_expected_yield runs without cache" do
      before do
        Rails.cache.clear
        allow(Rails.cache).to receive(:fetch).and_call_original
      end

      it "computes yield from tree data using sap_flow and stress" do
        tree = create(:tree, cluster: cluster, status: :active, latest_stress_index: 0.2)
        create(:telemetry_log, tree: tree, sap_flow: 2.0,
               temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
               acoustic_events: 2, growth_points: 10,
               bio_status: :homeostasis, metabolism_s: 1000)

        get "/oracle_visions", headers: forester_headers, as: :json

        expect(response).to have_http_status(:ok)
        # 2.0 sap × (1 − 0.2) × 24 / поріг — пін на ЧИСЛО, не на «якесь Numeric».
        expected = ((2.0 * 0.8 * 24) / TokenomicsEvaluatorWorker.emission_threshold).round(4)
        expect(response.parsed_body["emission_forecast"]).to be_within(0.0001).of(expected)
      end

      # 🔴 Ядро фіксу: дерево БЕЗ виміряного стресу не має ваги здоровʼя, тож воно
      # не входить у суму — але й не зникає мовчки. Доти `current_stress` віддавав
      # `0.0`, тобто множник `(1.0 − 0)`: невиміряне дерево віддавало ВЕСЬ свій sap
      # як ідеально здорове. Пін тримає обидві половини — число й покриття.
      it "leaves an unmeasured tree out of the sum and declares the coverage" do
        measured = create(:tree, cluster: cluster, status: :active, latest_stress_index: 0.5)
        unmeasured = create(:tree, cluster: cluster, status: :active, latest_stress_index: nil)
        [ measured, unmeasured ].each do |tree|
          create(:telemetry_log, tree: tree, sap_flow: 2.0,
                 temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
                 acoustic_events: 2, growth_points: 10,
                 bio_status: :homeostasis, metabolism_s: 1000)
        end

        get "/oracle_visions", headers: forester_headers, as: :json

        expect(response).to have_http_status(:ok)
        expected = ((2.0 * 0.5 * 24) / TokenomicsEvaluatorWorker.emission_threshold).round(4)
        expect(response.parsed_body["emission_forecast"]).to be_within(0.0001).of(expected)
        expect(response.parsed_body["emission_forecast_coverage"]).to eq("measured" => 1, "total" => 2)
      end

      # ⊥ Третій вхід, відмінний від обох вище: стрес ВИМІРЯНО, а телеметрії немає
      # (нічний прохід був, свіжих пакетів — ні). Дерево входить у покриття як
      # виміряне, але віддає нуль sap — інакше `&.` на відсутньому лозі лишався б
      # непройденою гілкою, тобто саме тією адресою, де ніхто не ходив.
      it "counts a measured tree with no telemetry as measured, contributing zero" do
        create(:tree, cluster: cluster, status: :active, latest_stress_index: 0.3)

        get "/oracle_visions", headers: forester_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["emission_forecast"]).to eq(0.0)
        expect(response.parsed_body["emission_forecast_coverage"]).to eq("measured" => 1, "total" => 1)
      end

      # ⊥ Межа: до фіксу цей вхід давав `1.0 - nil` → TypeError → 500 на ВСЬОМУ
      # ендпоінті, а не зіпсовану комірку.
      it "does not 500 when every active tree is unmeasured" do
        create(:tree, cluster: cluster, status: :active, latest_stress_index: nil)

        get "/oracle_visions", headers: forester_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["emission_forecast"]).to eq(0.0)
        expect(response.parsed_body["emission_forecast_coverage"]).to eq("measured" => 0, "total" => 1)
      end
    end
  end

  describe "POST /oracle_visions/simulate" do
    before do
      stub_const("SimulationWorker", Class.new do
        def self.perform_async(*args)
          "job-123"
        end
      end)
    end

    it "starts a simulation for admin" do
      post "/oracle_visions/simulate",
           params: { cluster_id: cluster.id, variables: { temp: 25 } },
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["job_id"]).to eq("job-123")
    end

    it "starts a simulation for admin when variables is omitted entirely" do
      post "/oracle_visions/simulate",
           params: { cluster_id: cluster.id },
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["job_id"]).to eq("job-123")
    end

    it "returns 403 for forester (simulate requires admin)" do
      post "/oracle_visions/simulate",
           params: { cluster_id: cluster.id },
           headers: forester_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for investor users" do
      post "/oracle_visions/simulate",
           params: { cluster_id: cluster.id },
           headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      post "/oracle_visions/simulate", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # =========================================================================
    # TENANT-ISOLATION: SimulationWorker walks Trees by cluster_id without
    # re-checking org. Admin from org A used to be able to fire a simulation
    # against org B's cluster — pattern matches firmware deploy guard.
    # =========================================================================
    it "returns 404 when cluster_id belongs to another organization" do
      other_org = create(:organization)
      other_cluster = create(:cluster, organization: other_org)

      post "/oracle_visions/simulate",
           params: { cluster_id: other_cluster.id, variables: { sigma: 10 } },
           headers: admin_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # ===========================================================================
  # TENANT-ISOLATION: visions and yield calculation must scope to current org.
  # Previously the index leaked global AiInsight + cached the protocol-wide
  # yield total under a single key.
  # ===========================================================================
  describe "GET /oracle_visions — cross-tenant scoping" do
    let(:foreign_org) { create(:organization) }
    let(:foreign_cluster) { create(:cluster, organization: foreign_org) }

    before { Rails.cache.clear }

    it "does not surface AiInsight rows from another organization" do
      own_tree = create(:tree, cluster: cluster)
      foreign_tree = create(:tree, cluster: foreign_cluster)
      own_vision = create(:ai_insight, analyzable: own_tree, target_date: 1.day.from_now)
      foreign_vision = create(:ai_insight, analyzable: foreign_tree, target_date: 1.day.from_now)

      get "/oracle_visions", headers: forester_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["visions"].map { |v| v["id"] }
      expect(ids).to include(own_vision.id)
      expect(ids).not_to include(foreign_vision.id)
    end

    it "caches emission forecast under a per-org key" do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch)
        .with("oracle_expected_yield_24h_org_#{organization.id}", expires_in: 1.hour)
        .and_return({ value: 2.5, measured: 3, total: 3 })

      get "/oracle_visions", headers: forester_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["emission_forecast"].to_f).to eq(2.5)

      # `allow` + `have_received` separates stub setup (test fixture) from
      # the behavioural assertion (the per-org key was used, the legacy
      # global key was not). This pattern keeps RSpec/StubbedMock happy.
      expect(Rails.cache).to have_received(:fetch)
        .with("oracle_expected_yield_24h_org_#{organization.id}", expires_in: 1.hour)
      expect(Rails.cache).not_to have_received(:fetch)
        .with("oracle_expected_yield_24h", anything)
    end
  end

  describe "yield calculation with real tree data" do
    it "iterates over active trees in find_each computing sap_flow and stress" do
      Rails.cache.clear
      Prosopite.pause if defined?(Prosopite)

      tree1 = create(:tree, cluster: cluster, status: :active)
      tree2 = create(:tree, cluster: cluster, status: :active)

      create(:telemetry_log, tree: tree1, sap_flow: 2.0,
             temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
             acoustic_events: 2, growth_points: 10,
             bio_status: :homeostasis, metabolism_s: 1000)

      create(:telemetry_log, tree: tree2, sap_flow: 3.0,
             temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
             acoustic_events: 2, growth_points: 10,
             bio_status: :homeostasis, metabolism_s: 1000)

      get "/oracle_visions", headers: forester_headers, as: :json
      expect(response).to have_http_status(:ok)
      # emission_forecast may be a string or numeric depending on JSON serialization
      forecast = response.parsed_body["emission_forecast"]
      expect(forecast.to_f).to be_a(Float)
    ensure
      Prosopite.resume if defined?(Prosopite)
    end

    it "handles tree with nil telemetry (sap_flow defaults to 0.0)" do
      Rails.cache.clear

      create(:tree, cluster: cluster, status: :active)

      get "/oracle_visions", headers: forester_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["emission_forecast"]).to be_a(Numeric)
    end
  end
end

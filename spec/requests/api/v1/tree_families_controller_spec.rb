# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TreeFamiliesController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }
  # Мутації TreeFamily = глобальні money/fraud-константи → лише super_admin (SEC).
  let(:super_admin) { create(:user, :super_admin, organization: organization) }
  let(:super_admin_headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

  let!(:scots_pine) { create(:tree_family, :scots_pine) }
  let!(:common_oak) { create(:tree_family, :common_oak) }

  describe "GET /tree_families" do
    context "when as JSON" do
      it "returns all tree families for admin" do
        get "/tree_families", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        names = response.parsed_body["data"].map { |f| f["name"] }
        expect(names).to include("Scots Pine", "Common Oak")
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/tree_families", headers: headers
        expect(response).to have_http_status(:ok)
      end

      # [UI.6] Роле-фільтр дій живе в компоненті, а ПРОВОДКА актора — у контролері.
      # Компонентна спека другої половини не бачить (конструює компонент напряму),
      # тож забутий kwarg лишив би її зеленою при повністю відкритих кнопках.
      # Негативний приклад для цього НЕ годиться: дефолт fail-closed ховає дії від
      # усіх, тож стереже проводку лише ПОЗИТИВНЕ твердження.
      it "показує мутаційні дії super_admin, але не звичайному admin" do
        get "/tree_families", headers: super_admin_headers
        expect(response.body).to include("+ Define DNA")

        get "/tree_families", headers: headers
        expect(response.body).to include("Species Name")     # сторінка та сама
        expect(response.body).not_to include("+ Define DNA")
      end
    end

    it "returns 403 for non-admin users" do
      get "/tree_families", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/tree_families", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /tree_families/:id" do
    context "when as JSON" do
      it "returns a specific tree family" do
        get "/tree_families/#{scots_pine.id}", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["name"]).to eq("Scots Pine")
      end
    end

    context "when as HTML" do
      # 🔴 [TEST.12 вісь D, друга група присуду D3] Сторінка несе `@family` з контролера.
      # Пін на наукову назву, а не на `name`: `name` рендериться ще й водяним знаком
      # (перші три літери) і в заголовку, тож пін на нього був би менш адресним.
      it "друкує ЗАПИТАНУ родину, а не порожню сторінку" do
        get "/tree_families/#{scots_pine.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(scots_pine.scientific_name)
      end
    end

    it "returns 403 for non-admin users" do
      get "/tree_families/#{scots_pine.id}", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /tree_families/new" do
    let(:headers) { super_admin_headers }

    it "renders the new family form for super_admin" do
      get "/tree_families/new", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin users" do
      get "/tree_families/new", headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /tree_families" do
    let(:headers) { super_admin_headers }

    let(:valid_params) do
      {
        tree_family: {
          name: "Silver Birch",
          scientific_name: "Betula pendula",
          critical_z_min: 6.0,
          critical_z_max: 42.0,
          carbon_sequestration_coefficient: 1.2
        }
      }
    end

    let(:invalid_params) do
      {
        tree_family: {
          name: "",
          critical_z_min: nil,
          critical_z_max: nil,
          carbon_sequestration_coefficient: nil
        }
      }
    end

    it "creates a new tree family with valid params" do
      expect {
        post "/tree_families", params: valid_params, headers: headers
      }.to change(TreeFamily, :count).by(1)

      # [UI.7] Ціль названа: create веде в СПИСОК, update — на сторінку запису, тож
      # «якийсь 3xx» не розрізняв двох сусідніх дій цього ж контролера.
      expect(response).to redirect_to(tree_families_path)
    end

    # [ARCH.84] Браузер шле ПОРОЖНІЙ РЯДОК за кожен незаповнений `number_field`,
    # і саме цього набору фікстура не мала: `valid_params` ці ключі просто
    # ОПУСКАЄ, тож `store_accessor` ніколи не отримував `""` і сюїта була зелена
    # за побудовою (`04_06 §B.2` BP 21 — у наборі немає того, що механізм мусить
    # відкинути). `allow_nil` порожнього рядка не покриває, тож обидві опційні
    # біологічні властивості були де-факто обовʼязковими, і єдиний UI-шлях
    # завести породу відповідав 422 на цілком легальному вводі.
    it "accepts the form's blank optional biological fields" do
      params = valid_params.deep_dup
      params[:tree_family][:foliage_density] = ""
      params[:tree_family][:bark_thickness] = ""

      expect {
        post "/tree_families", params: params, headers: headers, as: :json
      }.to change(TreeFamily, :count).by(1)

      expect(response).to have_http_status(:created)

      # Друга половина: порожнеча мусить осісти саме `nil`, а не `""` — рядок
      # у JSONB truthy, і живий fire-поріг (`fire_resistance_rating`) ним
      # арифметичить у `AlertDispatchService`.
      created = TreeFamily.find_by(name: "Silver Birch")
      expect(created.foliage_density).to be_nil
      expect(created.bark_thickness).to be_nil
    end

    context "when as JSON" do
      it "returns 201 with JSON body on success" do
        post "/tree_families", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:created)

        body = response.parsed_body
        expect(body["data"]["name"]).to eq("Silver Birch")
      end

      it "returns validation errors on failure" do
        post "/tree_families", params: invalid_params, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to have_key("errors")
      end
    end

    it "does not create with invalid params and re-renders form" do
      expect {
        post "/tree_families", params: invalid_params, headers: headers
      }.not_to change(TreeFamily, :count)

      # [SEC.25] 422, не 200: Turbo викидає `200` без редиректу на сабміт, тож
      # форма з помилками не показалась би зовсім.
      expect(response).to have_http_status(:unprocessable_content)

      # 🔴 Друга половина, якої бракувало саме тут: приклад звався «re-renders form»
      # і був зелений, тоді як форма перемальовувалась НІМОЮ — `TreeFamilies::Form`
      # не читав `.errors` взагалі, тож єдиним сигналом відмови лишалась зміна
      # заголовка сторінки.
      expect(response.body).to include(I18n.t("errors.api.validation_failed_title"))
      expect(response.body).to include("Name can&#39;t be blank")
    end

    it "returns 403 for non-admin users" do
      post "/tree_families", params: valid_params, headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for a plain org admin — species mutations require super_admin" do
      post "/tree_families", params: valid_params,
           headers: { "Authorization" => "Bearer #{admin_token}" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /tree_families/:id/edit" do
    let(:headers) { super_admin_headers }

    # 🔴 [TEST.12 вісь D] Пін доти був самим `:ok`. Це ЄДИНИЙ шлях у дереві, який
    # рендерить `TreeFamilies::Form` із ПЕРСИСТОВАНИМ записом — компонентна спека
    # подає непер­систований (`id: nil`), тож предзаповнення полів значеннями з БД
    # не перевіряв ніхто. А форма редагування без предзаповнення віддає чесні 200
    # і мовчки стирає дані при сабміті: `update` запише порожнє.
    it "предзаповнює форму значеннями РЕДАГОВАНОГО запису, а не порожнього" do
      get "/tree_families/#{scots_pine.id}/edit", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="#{scots_pine.name}"))
      expect(response.body).to include(%(value="#{scots_pine.scientific_name}"))
    end

    it "returns 403 for non-admin users" do
      get "/tree_families/#{scots_pine.id}/edit", headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /tree_families/:id" do
    let(:headers) { super_admin_headers }

    it "updates the tree family with valid params" do
      patch "/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "Updated Pine" } },
            headers: headers

      expect(response).to redirect_to(tree_family_path(scots_pine))
      expect(scots_pine.reload.name).to eq("Updated Pine")
    end

    it "re-renders form with invalid params" do
      patch "/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "" } },
            headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(scots_pine.reload.name).to eq("Scots Pine")
    end

    it "returns 403 for non-admin users" do
      patch "/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "Hacked" } },
            headers: investor_headers

      expect(response).to have_http_status(:forbidden)
    end

    context "when as JSON" do
      it "returns 200 with JSON body on success" do
        patch "/tree_families/#{scots_pine.id}",
              params: { tree_family: { name: "Updated Pine" } },
              headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]["name"]).to eq("Updated Pine")
      end

      it "returns validation errors on failure" do
        patch "/tree_families/#{scots_pine.id}",
              params: { tree_family: { name: "" } },
              headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to have_key("errors")
      end
    end
  end

  describe "DELETE /tree_families/:id" do
    it "is not routable because destroy route is not defined" do
      delete "/tree_families/#{scots_pine.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(TreeFamily.exists?(scots_pine.id)).to be true
    end
  end
end

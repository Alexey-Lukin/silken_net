# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ProvisioningController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )
    allow(HardwareKeyService).to receive(:provision).and_return(SecureRandom.hex(32).upcase)
    allow(PeaqRegistrationWorker).to receive(:perform_async)
    # [ARCH.119] Leg declared live: these examples are about device-type routing, not
    # about the activation gate — the gate has its own example below.
    allow(Peaq::DidRegistryService).to receive(:configured?).and_return(true)
    silence_broadcasts!(:tree_map)
  end

  describe "POST /provisioning/register" do
    let(:valid_params) do
      {
        provisioning: {
          hardware_uid: "AABBCCDD11223344",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }
    end

    it "rejects registration into another organization's cluster (IDOR)" do
      params = valid_params.deep_merge(provisioning: { cluster_id: other_cluster.id })
      expect {
        post "/provisioning/register", params: params, headers: headers, as: :json
      }.not_to change(Gateway, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects duplicate hardware_uid registration" do
      HardwareKey.create!(
        device_uid: "AABBCCDD11223344",
        aes_key_hex: SecureRandom.hex(32).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      post "/provisioning/register", params: valid_params, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to include("already registered")
    end

    # =========================================================================
    # [FW.54 Вісь 2] FW.24-guard знято: суфікс 511CEE01 — легітимна точка
    # DID-простору (firmware більше не емітує магічний fallback; DID = f(UID),
    # колізії ловить DB-unique на trees.did). Регресія: guard не повернувся.
    # =========================================================================
    context "with hardware_uid ending in the retired FW.24 magic" do
      it "provisions normally — no fallback-magic rejection" do
        # Валідний gateway-UID (SNET-Q-[8 HEX]) з суфіксом 511CEE01 — рівно
        # той false-positive, який старий guard хибно відкидав.
        magic_params = valid_params.deep_merge(
          provisioning: { hardware_uid: "SNET-Q-511CEE01" }
        )
        post "/provisioning/register", params: magic_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.body.to_s).not_to include("fallback")
      end
    end

    context "when registering a new gateway" do
      let(:gateway_params) do
        {
          provisioning: {
            hardware_uid: "SNET-Q-AA11BB22",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "successfully registers a gateway device" do
        post "/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["did"]).to eq("SNET-Q-AA11BB22")
        expect(body["key_derivation"]).to eq("hkdf-sha256")
      end

      # [SEC.11] Neither the AES key nor the Lorenz K_seed is ever
      # returned over the network — both are derived independently on
      # firmware via HKDF from PROVISIONING_MASTER_KEY.
      it "never returns aes_key, lorenz_seed, or warning in response [SEC.11]" do
        post "/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body).not_to have_key("aes_key")
        expect(body).not_to have_key("lorenz_seed")
        expect(body).not_to have_key("warning")
      end

      # [SEC.11] HardwareKey persists both AES key and K_seed, derived
      # deterministically from the pinned test PROVISIONING_MASTER_KEY.
      it "persists deterministic K_seed on HardwareKey [SEC.11]" do
        allow(HardwareKeyService).to receive(:provision).and_call_original

        post "/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        hw_key = HardwareKey.find_by(device_uid: body["did"])
        expect(hw_key.lorenz_seed_hex).to match(/\A[0-9A-F]{64}\z/)
        expect(hw_key.lorenz_seed_hex).to eq(SilkenNet::SeedDerivation.derive_seed(body["did"]))
        expect(hw_key.binary_lorenz_seed.bytesize).to eq(32)
      end
    end

    context "when registering a new tree" do
      # [FW.54] hardware_uid = 24-hex кремнієвий UID (golden g1 → SNET-80B12004)
      let(:tree_params) do
        {
          provisioning: {
            hardware_uid: "0039002F3138511538323634",
            device_type: "tree",
            cluster_id: own_cluster.id,
            family_id: tree_family.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "реєструє дерево з ДЕРИВОВАНИМ DID (murmur3-fmix32) + кремнієвим паспортом" do
        post "/provisioning/register", params: tree_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["did"]).to eq("SNET-80B12004")
        # [SEC.11] AES key is never returned in the response — firmware
        # derives it independently from PROVISIONING_MASTER_KEY.
        expect(body).not_to have_key("aes_key")

        tree = Tree.find_by!(did: "SNET-80B12004")
        expect(tree.silicon_uid_hex).to eq("0039002F3138511538323634")
      end

      it "enqueues PeaqRegistrationWorker for tree registration" do
        post "/provisioning/register", params: tree_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(PeaqRegistrationWorker).to have_received(:perform_async).with(Tree.last.id)
      end

      # [ARCH.119] Activation gate. Несконфігурована нога дала б 6 гарантовано провальних
      # виконань на КОЖНЕ дерево, і Sentry цього не показав би (`RegistrationError` в
      # `excluded_exceptions`). Пропуск нічого не губить — `peaq_did IS NULL` і є маркером,
      # який дренажить `PeaqBackfillWorker`; саме тому пін тримає ОБИДВА твердження.
      it "provisions the tree but enqueues NOTHING when the peaq leg is unconfigured" do
        allow(Peaq::DidRegistryService).to receive(:configured?).and_return(false)

        expect {
          post "/provisioning/register", params: tree_params, headers: headers, as: :json
        }.to change(Tree, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
        expect(Tree.last.peaq_did).to be_nil # маркер лишається — ре-арм має що знайти
      end

      # [ARCH.59] Єдиний носій межі транзакції на цьому сайті: enqueue стоїть
      # ПІСЛЯ коміту, тож мертвий Redis більше не скасовує вже провіжінений
      # вузол разом із записом монтажу. Мутація «повернути `perform_async`
      # усередину транзакції» червонить рівно цей приклад — сусіди її не бачать,
      # бо їхня точка збою (`HardwareKeyService.provision`) стоїть ДО enqueue.
      it "keeps the provisioned tree committed when the peaq enqueue fails" do
        allow(PeaqRegistrationWorker).to receive(:perform_async)
          .and_raise(StandardError.new("Redis unavailable"))

        expect {
          post "/provisioning/register", params: tree_params, headers: headers, as: :json
        }.to change(Tree, :count).by(1)

        expect(response).to have_http_status(:internal_server_error)
        # Уся транзакція закомічена, не лише сам вузол.
        expect(MaintenanceRecord.where(maintainable: Tree.last).count).to eq(1)
      end

      it "відкидає не-24-hex hardware_uid (422, жодних рядків)" do
        bad = tree_params.deep_merge(provisioning: { hardware_uid: "AABB11223344CCDD" })

        expect {
          post "/provisioning/register", params: bad, headers: headers, as: :json
        }.not_to change(Tree, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("24 hex")
      end
    end

    context "when ed25519_public_key is provided" do
      let(:ed25519_key_hex) { SecureRandom.hex(32) }
      let(:ed25519_gateway_params) do
        {
          provisioning: {
            hardware_uid: "SNET-Q-ED250001",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620,
            ed25519_public_key: ed25519_key_hex
          }
        }
      end

      before do
        # Allow real provisioning so HardwareKey is created before ed25519 update
        allow(HardwareKeyService).to receive(:provision).and_call_original
      end

      it "stores the Ed25519 public key on the hardware key" do
        post "/provisioning/register", params: ed25519_gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        hw_key = HardwareKey.find_by(device_uid: "SNET-Q-ED250001")
        expect(hw_key).to be_present
        expect(hw_key.ed25519_public_key_hex).to eq(ed25519_key_hex)
      end
    end

    context "when registering a gateway" do
      it "does not enqueue PeaqRegistrationWorker" do
        gateway_params = {
          provisioning: {
            hardware_uid: "SNET-Q-BB22CC33",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }

        post "/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
      end
    end

    context "when device_type is unknown" do
      let(:bad_type_params) do
        {
          provisioning: {
            hardware_uid: "AABBCCDD99887766",
            device_type: "quantum_sensor",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "returns internal server error" do
        post "/provisioning/register", params: bad_type_params, headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["error"]).to include("Core fault in the Ocean")
      end
    end

    context "when user is not a forester" do
      let(:subscriber) { create(:user, :subscriber, organization: organization) }
      let(:subscriber_token) { subscriber.generate_token_for(:api_access) }
      let(:subscriber_headers) { { "Authorization" => "Bearer #{subscriber_token}" } }

      it "returns forbidden" do
        post "/provisioning/register", params: valid_params, headers: subscriber_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when device fails validation" do
      let(:invalid_gateway_params) do
        {
          provisioning: {
            hardware_uid: "INVALIDUID",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "returns validation errors" do
        post "/provisioning/register", params: invalid_gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to be_present
      end
    end
  end

  describe "format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    # [TEST.10] Доти приклад приймав як успіх і робочу сторінку, і аварію сервера —
    # тобто не міг упасти в принципі, а фразу-виправдання про «шлях усе одно
    # пройдено» скопіювали по файлах. Саме така форма приховала сусідню сторінку
    # завантаження прошивки, яка віддавала аварію й не рендерила форми взагалі.
    it "renders the provisioning form" do
      get "/provisioning/new", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("hardware_uid")
    end

    it "renders HTML success after registering a gateway" do
      gateway_params = {
        provisioning: {
          hardware_uid: "SNET-Q-FF99EE88",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }

      post "/provisioning/register", params: gateway_params, headers: html_headers

      # [SEC.25] 🔴 Доти тут стояв `:ok` — і саме він цементував найдорожчу німоту
      # в дереві: успіх провізії рендерився `200` без редиректу, а Turbo такі
      # відповіді на сабміт викидає мовчки. Лісник тиснув «Provision», пристрій
      # створювався, і сторінка не ворушилась. Тепер PRG: 303 на сторінку самого
      # пристрою, де `uid` уже в шапці, і повідомлення у flash.
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(gateway_path(Gateway.find_by(uid: "SNET-Q-FF99EE88")))
    end

    it "renders HTML errors when device validation fails" do
      invalid_params = {
        provisioning: {
          hardware_uid: "INVALIDUID",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }

      post "/provisioning/register", params: invalid_params, headers: html_headers

      # [SEC.25] 422, не 200 — інакше Turbo викидає відповідь і форма з помилками
      # виглядає для лісника як мертва кнопка.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.content_type).to include("text/html")
    end

    # [SEC.25 Ф4] Три ранні гілки `#register` віддавали голий JSON. Пін саме на
    # ФОРМУ відповіді, не на статус: статуси не змінювались, тож пін на них лишався
    # б зеленим і на зламаній поверхні. Наявні приклади цих гілок форсують
    # `as: :json` і до HTML-половини сліпі за побудовою.
    it "renders the form, not a JSON blob, when the hardware UID is malformed" do
      post "/provisioning/register",
           params: { provisioning: { hardware_uid: "NOT24HEX", device_type: "tree",
                                     cluster_id: own_cluster.id, tree_family_id: tree_family.id,
                                     latitude: 49.4285, longitude: 32.0620 } },
           headers: html_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("hardware_uid")
    end

    it "renders the form, not a JSON blob, when the device is already provisioned" do
      # ⚠️ Ключ створюємо ЯВНО: `HardwareKeyService.provision` тут замокано, тож
      # звичайна повторна відправка форми впала б у модельну валідацію (422) і
      # 409-гілки не дістала б узагалі — приклад був би зелений про інший шлях.
      uid = "SNET-Q-AABBCCDD"
      HardwareKey.create!(
        device_uid: uid,
        aes_key_hex: SecureRandom.hex(32).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      post "/provisioning/register",
           params: { provisioning: { hardware_uid: uid, device_type: "gateway",
                                     cluster_id: own_cluster.id,
                                     latitude: 49.4285, longitude: 32.0620 } },
           headers: html_headers

      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("text/html")
      # 🔴 [SEC.25] Доти тут стояло `include("hardware_uid")` — рядок, який є в тілі
      # ЗАВЖДИ (це `name` інпута форми), тож пін не вмів упасти й не бачив би, що
      # причина відмови до людини не доїхала. Гілки 409/404 кладуть текст у
      # `@device.errors` вручну, тому саме його й треба міряти.
      expect(response.body).to include(I18n.t("flash.provisioning.uid_taken", uid: uid))
    end

    it "renders the form, not a JSON blob, for a cluster of another organization" do
      post "/provisioning/register",
           params: { provisioning: { hardware_uid: "SNET-Q-11223344", device_type: "gateway",
                                     cluster_id: other_cluster.id,
                                     latitude: 49.4285, longitude: 32.0620 } },
           headers: html_headers

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/html")
      # [SEC.25] Дзеркало сусіда вище: міряємо ПРИЧИНУ, не `name` інпута.
      expect(response.body).to include(I18n.t("errors.api.not_found", model: "Cluster"))
    end
  end
end

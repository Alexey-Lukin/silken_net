# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FirmwaresController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:api_token) { admin.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "POST /firmwares/:id/deploy" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "2.0.0", bytecode_payload: "AABBCCDD")
    end
    let(:cluster) { create(:cluster, organization: organization) }
    let!(:gateway) { create(:gateway, cluster: cluster) }

    before { OtaTransmissionWorker.clear }

    it "targets the gateway via pending_firmware_id (FW.60 poll-тракт, без push-enqueue)" do
      post "/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id, canary_percentage: 5 }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(5)
      expect(response.parsed_body["dispatched_gateways"]).to eq(1)
      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "defaults canary_percentage to 100 when not specified" do
      post "/firmwares/#{firmware.id}/deploy",
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(100)
    end

    it "clamps canary_percentage to valid range" do
      post "/firmwares/#{firmware.id}/deploy",
           params: { canary_percentage: 200 }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(100)
    end

    # =========================================================================
    # ANTI-ROLLBACK (SEC.20 Rails-half): firmware.id must STRICTLY exceed the
    # cluster hiwater — the Rails mirror of the Soldier Flash-KV 0x15 invariant.
    # =========================================================================
    it "rejects a stale deploy with 422 and enqueues nothing" do
      cluster.update!(ota_version_hiwater: firmware.id)

      post "/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("anti-rollback")
      expect(response.parsed_body["skipped_clusters"].sole["reason"]).to eq("rollback")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "rejects a deploy with no eligible gateways with 422" do
      gateway.update!(state: :maintenance)

      post "/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["skipped_clusters"].sole["reason"]).to eq("no_gateways")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "mixed whole-forest rejection carries BOTH skip reasons; stale message wins the headline" do
      cluster.update!(ota_version_hiwater: firmware.id) # rollback-skip
      empty_cluster = create(:cluster, organization: organization) # no_gateways-skip

      post "/firmwares/#{firmware.id}/deploy", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("anti-rollback")
      reasons = response.parsed_body["skipped_clusters"].to_h { |sc| [ sc["id"], sc["reason"] ] }
      expect(reasons).to eq(cluster.id => "rollback", empty_cluster.id => "no_gateways")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    # =========================================================================
    # INPUT GUARDS: the guards live in the controller (params + authz);
    # the dispatcher re-scopes tenancy as belt-and-suspenders.
    # =========================================================================
    it "rejects unknown target_type with 400 and does not enqueue" do
      post "/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Quantum" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("Tree", "Gateway")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "rejects target_type contradicting the firmware hardware type with 400" do
      firmware.update!(target_hardware_type: "Tree")

      post "/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Gateway", cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("Tree")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "accepts a matching target_type and reports the cluster target" do
      firmware.update!(target_hardware_type: "Tree")

      post "/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Tree", cluster_id: cluster.id, canary_percentage: 25 },
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["dispatched_gateways"]).to eq(1)
      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
    end

    it "rejects cluster_id from another organization with 404" do
      other_org = create(:organization)
      other_cluster = create(:cluster, organization: other_org)

      post "/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: other_cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(OtaTransmissionWorker.jobs).to be_empty
    end
  end

  describe "GET /firmwares (index)" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "3.0.0", bytecode_payload: "AABBCCDD")
    end

    it "returns firmware list as JSON" do
      get "/firmwares", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to be_an(Array)
    end

    it "renders HTML dashboard for firmware index" do
      get "/firmwares", headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # Секція «Active Evolutions» рендерить `turbo_stream_from "ota_channel_{uid}"` —
    # єдиний стрім застосунку, чиє імʼя НЕ несе org-токена, тобто безпечний лише
    # транзитивно: рівно настільки, наскільки `@active_ota_gateways` скоуплений.
    # Досі жодна request-спека цієї гілки не проходила — приклади не створювали
    # ані `updating`, ані затаргеченого шлюзу, тож секція не рендерилась узагалі
    # і скидання префікса `org.` лишалось би зеленим.
    # ⚠️ Форма піна — РІВНІСТЬ МНОЖИНИ, не «містить свій»: імʼя без org-токена
    # означає, що дефект виглядає як ЗАЙВИЙ стрім на сторінці, а не як
    # відсутній свій. Тому потрібен і чужий шлюз у тому ж стані.
    context "when OTA campaigns are live" do
      let(:own_gateway) { create(:gateway, cluster: create(:cluster, organization: organization), state: :updating) }
      let(:foreign_gateway) do
        create(:gateway, cluster: create(:cluster, organization: create(:organization)), state: :updating)
      end

      it "subscribes only to the viewer's OWN gateways' OTA channels" do
        own_gateway
        foreign_gateway

        get "/firmwares", headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

        streams = response.body.scan(/signed-stream-name="([^"]+)"/).flatten
                          .map { |name| Turbo::StreamsChannel.verified_stream_name(name) }
        expect(streams).to eq([ "ota_channel_#{own_gateway.uid}" ])
      end
    end

    # 🔴 [ARCH.83, присуд founder 2026-08-13] Каталог образів тенанта не має за
    # побудовою, а сторінка кликала `acting_organization!` заради самої лише панелі
    # інвентаря — тож платформений адмін (обидва сіджені super_admin створюються без
    # організації) не бачив реєстру прошивок узагалі. Приклади вище цього не ловили:
    # усі будують актора З організацією, тобто ходять входом, якого перший вхід не дає.
    context "when the super_admin has not adopted a tenant yet" do
      let(:platform_admin) { create(:user, :super_admin, organization: nil) }
      let(:platform_headers) { { "Authorization" => "Bearer #{platform_admin.generate_token_for(:api_access)}" } }

      it "віддає глобальний каталог образів, а не 422 «немає організації»" do
        get "/firmwares", headers: platform_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].map { |f| f["version"] }).to include("3.0.0")
      end

      # ⚠️ Панель інвентаря org-скоуплена, тож без контексту вона НЕВИМІРЯНА, а не
      # порожня: `{}` надрукував би тиху нульову статистику по кожній версії — рівно
      # клас [ARCH.84]. Пін цілиться в текст стану, бо саме він розрізняє два світи.
      it "показує панель інвентаря як невиміряну, не як нульову" do
        get "/firmwares", headers: { "Authorization" => "Bearer #{platform_admin.generate_token_for(:api_access)}",
                                     "Accept" => "text/html" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("firmwares.index.inventory_no_context"))
        expect(response.body).not_to include(I18n.t("firmwares.index.queens"))
      end

      # ⊥ Межа присуду: `#inventory` віддає ВИКЛЮЧНО org-скоуплені дані, тобто ресурс
      # тенантний — на нього діє інша, теж ратифікована політика (однакове 422), і
      # знімати банг там було б помилкою. Цей приклад стереже саме межу.
      it "лишає суто тенантний #inventory за 422 — банг там правильний" do
        get "/firmwares/inventory", headers: platform_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["code"]).to eq("no_organization")
      end
    end
  end

  describe "GET /firmwares/new" do
    # 🔴 Доти цей приклад приймав як успіх і 200, і 500 — і саме це ховало те, що
    # сторінка віддавала рівно 500 і не рендерила форми ВЗАГАЛІ: `form_with(model:)`
    # виводив неіснуючий `bio_contract_firmwares_path`. Тобто завантажити прошивку
    # через UI було неможливо, а сюїта лишалась зеленою [SEC.25 / TEST.10].
    it "рендерить сторінку із ЖИВОЮ формою, що цілить у правильний маршрут" do
      get "/firmwares/new", headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include('action="/firmwares"')
      # Скоуп параметрів мусить збігтися з `params.require(:firmware)` у контролері —
      # дефолтний вивів би `bio_contract_firmware[...]`.
      expect(response.body).to include('name="firmware[version]"')
    end
  end

  describe "POST /firmwares (create)" do
    # 🔴 Round-trip форма⟷контролер: склад полів зішкрібається з ЖИВОЇ розмітки, а не
    # друкується тут. Рукописний список пінив би те, що надрукував автор, і рівно цей
    # дрейф прожив непоміченим: форма слала `firmware[target_hardware]` і
    # `firmware[notes]` — колонок під них НЕМАЄ, тож мас-присвоєння кидало
    # `ActiveModel::UnknownAttributeError`, і кожен сабміт віддавав 500.
    # Рендер при цьому справний і мовчить: `form_with` виставляє
    # `allow_method_names_outside_object`, тож читання неіснуючого поля дає nil —
    # тому компонентна спека на реальній моделі лишалась зеленою.
    it "форма переживає власний сабміт: кожне поле, яке вона рендерить, контролер приймає" do
      html_headers = { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      get "/firmwares/new", headers: html_headers
      rendered_fields = response.body.scan(/name="firmware\[([a-z_]+)\]"/).flatten.uniq
      # Пін на РОЗМІР множини: зішкрібання, що не знайшло нічого, зробило б приклад
      # вакуумним — порожній payload проходить будь-яким контролером.
      expect(rendered_fields).to include("version", "target_hardware_type")

      known = {
        "version" => "7.7.7",
        "target_hardware_type" => BioContractFirmware::HARDWARE_TYPES.first,
        "binary_file" => Rack::Test::UploadedFile.new(
          StringIO.new("\xDE\xAD".b), "application/octet-stream", true, original_filename: "fw.bin"
        )
      }
      post "/firmwares",
           params: { firmware: rendered_fields.index_with { |f| known.fetch(f, "") } },
           headers: html_headers

      expect(response).to redirect_to(firmwares_path)
      expect(BioContractFirmware.find_by(version: "7.7.7")&.target_hardware_type)
        .to eq(BioContractFirmware::HARDWARE_TYPES.first)
    end

    # Дзеркало round-trip'а з боку API: застарілий клієнт шле ключі, яких на моделі
    # немає. Доти вони стояли в `permit`, тобто летіли в мас-присвоєння й валили
    # сервер; тепер strong-params відкидає їх мовчки, і 500 неможливий незалежно від
    # того, що надішле клієнт.
    it "ключ, якого модель не має, більше не валить сервер" do
      post "/firmwares",
           params: { firmware: { version: "8.8.8", bytecode_payload: "DEADBEEF",
                                 target_hardware: "stm32_l0", notes: "легасі-клієнт" } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "creates firmware successfully as JSON" do
      post "/firmwares",
           params: { firmware: { version: "4.0.0", bytecode_payload: "DEADBEEF" } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      # Відповідь не повертає завантажений байткод: голий `@firmware` серіалізує
      # ВСІ колонки, тобто відсилав би до 40 МБ hex назад клієнтові.
      expect(response.parsed_body["firmware"]).not_to have_key("bytecode_payload")
    end

    # 🔴 Доти приймалось 200 або 500 — множина, що навіть не містила 422, який ця
    # гілка мала б віддавати після фіксу SEC.25. Тобто приклад був зелений САМЕ
    # тому, що шлях падав. Фраза-підстава про «Phlex may not render» ховала
    # реальний `NoMethodError` на неіснуючому маршрут-хелпері [TEST.10].
    it "повертає форму з 422 і ПОКАЗУЄ причину відмови" do
      post "/firmwares",
           params: { firmware: { version: "", bytecode_payload: "" } },
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      # Пін на СПОЖИВАЧА помилок, не лише на статус: форма роками поверталась без
      # жодного пояснення, бо `errors` нікуди не рендерились.
      expect(response.body).to include(I18n.t("errors.api.validation_failed_title"))
    end

    it "завеликий бінар віддає браузерові форму з поясненням, а не JSON-блоб" do
      oversized = Rack::Test::UploadedFile.new(
        StringIO.new("\x00" * (Api::V1::FirmwaresController::MAX_FIRMWARE_SIZE + 1)),
        "application/octet-stream",
        true,
        original_filename: "huge.bin"
      )

      post "/firmwares",
           params: { firmware: { version: "9.9.9", binary_file: oversized } },
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(
        I18n.t("flash.firmwares.file_too_large", limit: Api::V1::FirmwaresController::MAX_FIRMWARE_SIZE / 1.megabyte)
      )
    end

    # =========================================================================
    # SIZE BYPASS GUARD: clients posting bytecode_payload directly (no
    # multipart upload) used to skip MAX_FIRMWARE_SIZE. The cap is now
    # enforced against the hex string length (2× binary size).
    # =========================================================================
    it "rejects oversized bytecode_payload with 422" do
      huge_hex = "AA" * (Api::V1::FirmwaresController::MAX_BYTECODE_PAYLOAD_HEX_SIZE / 2 + 1)
      post "/firmwares",
           params: { firmware: { version: "9.9.9", bytecode_payload: huge_hex } },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "POST /firmwares/:id/deploy (HTML format)" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "5.0.0", bytecode_payload: "AABBCCDD")
    end
    let(:cluster) { create(:cluster, organization: organization) }

    before { OtaTransmissionWorker.clear }

    it "redirects with a notice on successful HTML deploy (the UI one-click path)" do
      gw = create(:gateway, cluster: cluster)

      post "/firmwares/#{firmware.id}/deploy",
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      # `pending`, не `success`: на момент показу жоден пристрій ще нічого не
      # отримав — наказ лише поставлено в чергу, і сам текст ключа це й каже.
      expect(flash[:pending]).to be_present
      expect(gw.reload.pending_firmware_id).to eq(firmware.id)
    end

    it "redirects with an alert when nothing was dispatched" do
      post "/firmwares/#{firmware.id}/deploy",
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
      expect(OtaTransmissionWorker.jobs).to be_empty
    end
  end
end

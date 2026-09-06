# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Controller coverage — uncovered paths" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  let(:gateway) { create(:gateway, cluster: cluster) }
  let(:user) { create(:user, organization: organization, password: "password12345") }
  let(:forester) { create(:user, :forester, organization: organization, password: "password12345") }
  let(:admin) { create(:user, :admin, organization: organization, password: "password12345") }

  def json_headers = { "Accept" => "application/json" }
  def auth_headers = json_headers.merge("Authorization" => "Bearer #{user.generate_token_for(:api_access)}")
  def forester_headers = json_headers.merge("Authorization" => "Bearer #{forester.generate_token_for(:api_access)}")
  def admin_headers = json_headers.merge("Authorization" => "Bearer #{admin.generate_token_for(:api_access)}")

  def unique_hardware_uid
    "UID#{SecureRandom.hex(4).upcase}"
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
    silence_broadcasts!(:wallet_balance, :tree_map)
  end

  # ==========================================================================
  # 1. SESSIONS CONTROLLER
  # ==========================================================================
  describe "SessionsController" do
    describe "POST /login (JSON)" do
      it "returns token and user info on valid credentials" do
        post "/login",
             params: { email: user.email_address, password: "password12345" },
             headers: json_headers

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json["token"]).to be_present
        expect(json["user"]["email"]).to eq(user.email_address)
        expect(json["user"]["role"]).to eq(user.role)
        expect(json["user"]["full_name"]).to eq(user.full_name)
      end

      it "creates a Session record on successful login" do
        expect {
          post "/login",
               params: { email: user.email_address, password: "password12345" },
               headers: json_headers
        }.to change(Session, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it "returns 401 on invalid credentials" do
        post "/login",
             params: { email: user.email_address, password: "wrongpassword1" },
             headers: json_headers

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["error"]).to be_present
      end

      it "returns 401 for non-existent email" do
        post "/login",
             params: { email: "nobody@example.com", password: "password12345" },
             headers: json_headers

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "DELETE /logout (JSON)" do
      # БЕЗ prepend-стабів: `current_session` визначений НА контролері
      # (старий around-хук препендив анонімний модуль за хибною преміссою
      # «методу нема» — а Module#prepend незворотний, тож ВСЯ решта сюїти
      # після цього прикладу тестувала підмінений метод, і coverage рядків
      # 80-82 плавав за сідом; знахідка seed-діффа TEST.1,
      # scripts/coverage_seed_diff.rb).
      it "returns success message when logged in" do
        post "/login",
             params: { email: user.email_address, password: "password12345" },
             headers: json_headers

        expect(response).to have_http_status(:created)
        token = response.parsed_body["token"]

        delete "/logout",
               headers: json_headers.merge("Authorization" => "Bearer #{token}")

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to be_present
      end
    end
  end

  # ==========================================================================
  # 2. MAINTENANCE RECORDS CONTROLLER
  # ==========================================================================
  describe "MaintenanceRecordsController" do
    let!(:maintenance_record) do
      create(:maintenance_record,
             maintainable: tree,
             user: forester,
             action_type: :inspection,
             performed_at: 1.hour.ago,
             notes: "Routine inspection of the node completed successfully.")
    end

    describe "GET /maintenance_records — with filtering" do
      it "filters by maintainable_type and maintainable_id" do
        get "/maintenance_records",
            params: { maintainable_type: "Tree", maintainable_id: tree.id },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["data"]).to be_an(Array)
      end

      it "filters by action_type" do
        get "/maintenance_records",
            params: { action_type: "inspection" },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["data"]).to be_an(Array)
      end

      it "filters by date range" do
        get "/maintenance_records",
            params: { from: 2.days.ago.iso8601, to: Time.current.iso8601 },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /maintenance_records — validation error" do
      # [E.20] JSON-гілка `create` вимагає `Idempotency-Key` і віддає 400 РАНІШЕ
      # за валідацію, тож без нього обидва приклади нижче доводили б формат
      # запиту замість валідації моделі, яку називають їхні імена.
      let(:idem_headers) { forester_headers.merge("Idempotency-Key" => SecureRandom.uuid) }

      it "returns validation errors for invalid data" do
        post "/maintenance_records",
             params: { maintenance_record: { notes: "", action_type: nil } },
             headers: idem_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
        expect(json["errors"].length).to be > 0
      end

      it "returns validation errors when notes are too short" do
        post "/maintenance_records",
             params: {
               maintenance_record: {
                 maintainable_type: "Tree",
                 maintainable_id: tree.id,
                 action_type: "inspection",
                 performed_at: 1.hour.ago,
                 notes: "Short"
               }
             },
             headers: idem_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end
    end

    describe "PATCH /maintenance_records/:id — update" do
      it "updates record successfully" do
        patch "/maintenance_records/#{maintenance_record.id}",
              params: { maintenance_record: { notes: "Updated notes for the inspection record here." } },
              headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to be_present
        expect(json["record"]).to be_present
      end

      it "returns validation errors on invalid update" do
        patch "/maintenance_records/#{maintenance_record.id}",
              params: { maintenance_record: { notes: "" } },
              headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end
    end

    describe "PATCH /maintenance_records/:id/verify" do
      it "verifies hardware state successfully" do
        # [UI.7] verify тепер звіряє пульс заліза: вузол мусив вийти в ефір
        # ПІСЛЯ performed_at, інакше guard віддає 422 ще до update.
        tree.update!(last_seen_at: 10.minutes.ago)
        patch "/maintenance_records/#{maintenance_record.id}/verify",
              headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["hardware_verified"]).to be true
        expect(json["message"]).to include(I18n.t("flash.maintenance.hardware_verified"))
      end

      it "returns error when verify update fails" do
        # [UI.7] Пульс обовʼязковий і тут: без нього guard віддає 422 РАНІШЕ за
        # update, мок не стріляє, а гілка «update fails» лишається невідвіданою
        # при зеленому статус-піні. Тому пін несе ПРЕДМЕТ: guard-гілка відповідає
        # `error:`-рядком, цільова — `errors:`-масивом.
        tree.update!(last_seen_at: 10.minutes.ago)
        allow_any_instance_of(MaintenanceRecord).to receive(:update).and_return(false)
        allow_any_instance_of(MaintenanceRecord).to receive(:errors).and_return(
          instance_double(ActiveModel::Errors, full_messages: [ "Hardware verification failed" ])
        )

        patch "/maintenance_records/#{maintenance_record.id}/verify",
              headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to eq([ "Hardware verification failed" ])
      end
    end

    describe "GET /maintenance_records/:id (JSON)" do
      it "returns record details" do
        get "/maintenance_records/#{maintenance_record.id}",
            headers: forester_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ==========================================================================
  # 3. FIRMWARES CONTROLLER
  # ==========================================================================
  describe "FirmwaresController" do
    describe "POST /firmwares — with binary_file upload" do
      it "creates firmware from binary file upload" do
        # Create a small binary file for upload
        binary_content = "\x00\x01\x02\x03\xAA\xBB\xCC\xDD"
        file = Tempfile.new([ "firmware", ".bin" ])
        file.binmode
        file.write(binary_content)
        file.rewind

        uploaded_file = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")

        post "/firmwares",
             params: { firmware: { version: "99.0.0", binary_file: uploaded_file } },
             headers: admin_headers

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json["firmware"]).to be_present

        firmware = BioContractFirmware.find_by(version: "99.0.0")
        expect(firmware).to be_present
        expect(firmware.bytecode_payload).to be_present

        file.close
        file.unlink
      end

      it "rejects firmware file exceeding size limit" do
        # Stub ActionDispatch::Http::UploadedFile#size to simulate a file over 20 MB
        allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(21.megabytes)

        small_file = Tempfile.new([ "firmware_large", ".bin" ])
        small_file.binmode
        small_file.write("\x00" * 64)
        small_file.rewind

        uploaded_file = Rack::Test::UploadedFile.new(small_file.path, "application/octet-stream")

        post "/firmwares",
             params: { firmware: { version: "99.1.0", binary_file: uploaded_file } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["error"]).to include("limit")

        small_file.close
        small_file.unlink
      end
    end

    describe "POST /firmwares — validation error" do
      it "returns validation errors for missing version" do
        post "/firmwares",
             params: { firmware: { version: "", bytecode_payload: "AABB" } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end

      it "returns validation errors for invalid bytecode" do
        post "/firmwares",
             params: { firmware: { version: "99.2.0", bytecode_payload: "NOT_HEX!" } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end

      it "returns validation errors for duplicate version" do
        create(:bio_contract_firmware, version: "99.3.0")

        post "/firmwares",
             params: { firmware: { version: "99.3.0", bytecode_payload: "AABB" } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end
    end
  end

  # ==========================================================================
  # 4. PROVISIONING CONTROLLER
  # ==========================================================================
  describe "ProvisioningController" do
    before do
      allow(HardwareKeyService).to receive(:provision).and_return("A" * 64)
    end

    describe "POST /provisioning/register — unknown device_type" do
      it "returns error for unknown device type" do
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: unique_hardware_uid,
                 device_type: "satellite",
                 cluster_id: cluster.id
               }
             },
             headers: forester_headers

        expect(response).to have_http_status(:internal_server_error)
        json = response.parsed_body
        expect(json["error"]).to be_present
      end
    end

    # [TEST.10] Обидва приклади тут приймали множину `{422, 500}` і хедж
    # `json["errors"] || json["error"]`, тобто не могли сказати, ЯКА гілка
    # відповіла. Вимір показав, що перший ніколи не доходив до валідації:
    # `unique_hardware_uid` = "UID"+8hex, а `DidDerivation::UID_HEX_FORMAT`
    # вимагає рівно 24 hex — спрацьовував UID-guard. Назва обіцяла «missing
    # family», гілка була інша, і НІ ОДНА з двох не мала власного піна. Тепер
    # ключ відповіді розрізняє гілки: `error` (однина) = guard, `errors`
    # (множина) = валідація моделі.
    describe "POST /provisioning/register — відмови" do
      it "rejects a tree whose hardware_uid is not a 24-hex silicon UID" do
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "UID00DEADBEEF",
                 device_type: "tree",
                 cluster_id: cluster.id,
                 family_id: tree_family.id
               }
             },
             headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["error"]).to include("UID00DEADBEEF")
        expect(json).not_to have_key("errors")
        expect(Tree.count).to eq(0)
      end

      it "rejects a tree with a valid silicon UID but no family" do
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "0039002F3138511538323634",
                 device_type: "tree",
                 cluster_id: cluster.id,
                 family_id: nil
               }
             },
             headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        # [I18N.1] Асоціація зветься `tree_family`, а людині її називає локаль:
        # `attributes.tree_family` = «Species» (домашній термін екрана видів),
        # тож якір на імені КОЛОНКИ тут був заявою про `String#humanize`.
        expect(response.parsed_body["errors"]).to include(a_string_matching(/species/i))
        expect(Tree.count).to eq(0)
      end

      it "rejects a gateway with a blank uid" do
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "",
                 device_type: "gateway",
                 cluster_id: cluster.id
               }
             },
             headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to include(a_string_matching(/uid/i))
        expect(Gateway.count).to eq(0)
      end
    end
  end

  # ==========================================================================
  # 5. BASE CONTROLLER — error handlers
  # ==========================================================================
  describe "BaseController error handling" do
    describe "ActionController::ParameterMissing → 400" do
      it "returns 400 when required params are missing" do
        # POST to maintenance_records without the required :maintenance_record key.
        # [E.20] `Idempotency-Key` присутній НАВМИСНО: без нього 400 приходив би
        # від гарда ідемпотентності, і приклад доводив би не `ParameterMissing`,
        # а сусідній механізм — при тому самому статусі.
        post "/maintenance_records",
             params: { wrong_key: { notes: "test" } },
             headers: forester_headers.merge("Idempotency-Key" => SecureRandom.uuid)

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to include("parameter")
      end
    end

    describe "ActiveRecord::RecordNotFound → 404" do
      it "returns 404 for non-existent record" do
        get "/maintenance_records/999999999",
            headers: forester_headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to be_present
      end
    end
  end

  # ==========================================================================
  # 6. SYSTEM HEALTH CONTROLLER
  # ==========================================================================
  describe "SystemHealthController" do
    describe "GET /system_health" do
      it "returns health status with sidekiq stats" do
        # Require sidekiq/api for Stats class
        require "sidekiq/api"

        stats_double = instance_double(Sidekiq::Stats,
                                        enqueued: 42,
                                        processed: 1000,
                                        failed: 5,
                                        workers_size: 16,
                                        queues: { "uplink" => 10, "default" => 32 })
        allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)

        get "/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["checked_at"]).to be_present
        expect(json["sidekiq"]).to be_present
        expect(json["sidekiq"]["enqueued"]).to eq(42)
        expect(json["sidekiq"]["processed"]).to eq(1000)
        expect(json["sidekiq"]["failed"]).to eq(5)
        expect(json["database"]).to be_present
      end

      it "reports database status" do
        get "/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["database"]["connected"]).to be true
      end

      it "handles database connection error gracefully" do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError.new("DB down"))

        get "/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["database"]["connected"]).to be false
        # [SEC]: сирий текст винятку не тече клієнту.
        expect(json["database"].to_s).not_to include("DB down")
      end

      # [ARCH.81] Доти тут стояв «port open path», що підробляв `TCPSocket` і
      # пінив `alive: true` — єдине місце в усій сюїті, де живий інтейк узагалі
      # спостерігався, і спостерігався він лише тому, що сокет був фальшивий.
      # Реальна проба — UDP-раунд-тріп із байт-точною звіркою; тут пінимо, що
      # відповідь описує СТАН проби, а не булеву вигадку.
      it "reports the CoAP intake by probe state, not by a faked socket" do
        get "/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["coap_listener"]).to have_key("status")
        expect(json["coap_listener"]).not_to have_key("alive")
        expect(json["coap_listener"]["status"]).to be_in(%w[alive unreachable wire_mismatch not_configured check_failed])
      end
    end
  end

  # ==========================================================================
  # 7. NOTIFICATIONS CONTROLLER
  # ==========================================================================
  describe "NotificationsController" do
    describe "PATCH /notifications/settings — validation error" do
    end

    describe "GET /notifications/settings" do
      it "returns current notification channel settings" do
        get "/notifications/settings",
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["user_id"]).to eq(user.id)
        expect(json["channels"]).to include("email", "push_token")
      end
    end
  end

  # ==========================================================================
  # 8. SETTINGS CONTROLLER
  # ==========================================================================
  describe "SettingsController" do
    describe "PATCH /settings — validation error" do
      it "returns errors for invalid organization data" do
        patch "/settings",
              params: { organization: { name: "", billing_email: "not-an-email" } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
        expect(json["errors"].length).to be > 0
      end

      it "returns errors for invalid crypto address" do
        patch "/settings",
              params: { organization: { crypto_public_address: "invalid-address" } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end

      it "returns errors for out-of-range alert threshold" do
        patch "/settings",
              params: { organization: { alert_threshold_critical_z: 999 } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end
    end

    describe "GET /settings" do
      it "returns organization settings" do
        get "/settings",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["organization"]).to be_present
        expect(json["organization"]["name"]).to eq(organization.name)
        expect(json["organization"]["billing_email"]).to eq(organization.billing_email)
      end
    end
  end
end

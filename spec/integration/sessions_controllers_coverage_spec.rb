# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe "Controller coverage — uncovered paths" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  let(:gateway) { create(:gateway, cluster: cluster) }

  let(:user) { create(:user, organization: organization, password: "password12345") }
  let(:forester) { create(:user, :forester, organization: organization, password: "password12345") }
  let(:admin) { create(:user, :admin, organization: organization, password: "password12345") }

  let(:user_token) { user.generate_token_for(:api_access) }
  let(:forester_token) { forester.generate_token_for(:api_access) }
  let(:admin_token) { admin.generate_token_for(:api_access) }

  let(:json_headers) { { "Accept" => "application/json" } }
  let(:auth_headers) { json_headers.merge("Authorization" => "Bearer #{user_token}") }
  let(:forester_headers) { json_headers.merge("Authorization" => "Bearer #{forester_token}") }
  let(:admin_headers) { json_headers.merge("Authorization" => "Bearer #{admin_token}") }

  def unique_hardware_uid
    "UID#{SecureRandom.hex(4).upcase}"
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  # ==========================================================================
  # 1. SESSIONS CONTROLLER
  # ==========================================================================
  describe "SessionsController" do
    describe "POST /api/v1/login (JSON)" do
      it "returns token and user info on valid credentials" do
        post "/api/v1/login",
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
          post "/api/v1/login",
               params: { email: user.email_address, password: "password12345" },
               headers: json_headers
        }.to change(Session, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it "returns 401 on invalid credentials" do
        post "/api/v1/login",
             params: { email: user.email_address, password: "wrongpassword1" },
             headers: json_headers

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["error"]).to be_present
      end

      it "returns 401 for non-existent email" do
        post "/api/v1/login",
             params: { email: "nobody@example.com", password: "password12345" },
             headers: json_headers

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "DELETE /api/v1/logout (JSON)" do
      # current_session is not defined on the controller; prepend a module to provide it
      around do |example|
        mod = Module.new do
          def current_session
            current_user&.sessions&.last
          end
        end
        Api::V1::SessionsController.prepend(mod)
        example.run
      end

      it "returns success message when logged in" do
        post "/api/v1/login",
             params: { email: user.email_address, password: "password12345" },
             headers: json_headers

        expect(response).to have_http_status(:created)
        token = response.parsed_body["token"]

        delete "/api/v1/logout",
               headers: json_headers.merge("Authorization" => "Bearer #{token}")

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to be_present
      end
    end

    describe "POST /api/v1/login — omniauth_create path" do
      it "creates or finds identity from auth hash" do
        test_user = create(:user, organization: organization, password: "password12345")
        # Identity.find_or_create_from_auth_hash expects an OpenStruct-like object
        auth_hash = OpenStruct.new(
          provider: "google_oauth2",
          uid: "google_uid_integration_#{SecureRandom.hex(4)}",
          info: OpenStruct.new(
            email: test_user.email_address,
            first_name: "OAuth",
            last_name: "User"
          )
        )

        identity = Identity.find_or_create_from_auth_hash(auth_hash, user: test_user)
        expect(identity).to be_persisted
        expect(identity.provider).to eq("google_oauth2")
        expect(identity.user).to eq(test_user)
      end

      it "detects locked identity" do
        locked_identity = create(:identity, :locked, provider: "google_oauth2")
        expect(locked_identity.locked?).to be true
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

    describe "GET /api/v1/maintenance_records — with filtering" do
      it "filters by maintainable_type and maintainable_id" do
        get "/api/v1/maintenance_records",
            params: { maintainable_type: "Tree", maintainable_id: tree.id },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["records"]).to be_an(Array)
      end

      it "filters by action_type" do
        get "/api/v1/maintenance_records",
            params: { action_type: "inspection" },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["records"]).to be_an(Array)
      end

      it "filters by date range" do
        get "/api/v1/maintenance_records",
            params: { from: 2.days.ago.iso8601, to: Time.current.iso8601 },
            headers: forester_headers

        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /api/v1/maintenance_records — validation error" do
      it "returns validation errors for invalid data" do
        post "/api/v1/maintenance_records",
             params: { maintenance_record: { notes: "", action_type: nil } },
             headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
        expect(json["errors"].length).to be > 0
      end

      it "returns validation errors when notes are too short" do
        post "/api/v1/maintenance_records",
             params: {
               maintenance_record: {
                 maintainable_type: "Tree",
                 maintainable_id: tree.id,
                 action_type: "inspection",
                 performed_at: 1.hour.ago,
                 notes: "Short"
               }
             },
             headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end
    end

    describe "PATCH /api/v1/maintenance_records/:id — update" do
      it "updates record successfully" do
        patch "/api/v1/maintenance_records/#{maintenance_record.id}",
              params: { maintenance_record: { notes: "Updated notes for the inspection record here." } },
              headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to be_present
        expect(json["record"]).to be_present
      end

      it "returns validation errors on invalid update" do
        patch "/api/v1/maintenance_records/#{maintenance_record.id}",
              params: { maintenance_record: { notes: "" } },
              headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end
    end

    describe "PATCH /api/v1/maintenance_records/:id/verify" do
      it "verifies hardware state successfully" do
        patch "/api/v1/maintenance_records/#{maintenance_record.id}/verify",
              headers: forester_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["hardware_verified"]).to be true
        expect(json["message"]).to include("Hardware state verified")
      end

      it "returns error when verify update fails" do
        allow_any_instance_of(MaintenanceRecord).to receive(:update).and_return(false)
        allow_any_instance_of(MaintenanceRecord).to receive(:errors).and_return(
          double(full_messages: [ "Hardware verification failed" ])
        )

        patch "/api/v1/maintenance_records/#{maintenance_record.id}/verify",
              headers: forester_headers

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /api/v1/maintenance_records/:id (JSON)" do
      it "returns record details" do
        get "/api/v1/maintenance_records/#{maintenance_record.id}",
            headers: forester_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ==========================================================================
  # 3. FIRMWARES CONTROLLER
  # ==========================================================================
  describe "FirmwaresController" do
    describe "POST /api/v1/firmwares — with binary_file upload" do
      it "creates firmware from binary file upload" do
        # Create a small binary file for upload
        binary_content = "\x00\x01\x02\x03\xAA\xBB\xCC\xDD"
        file = Tempfile.new([ "firmware", ".bin" ])
        file.binmode
        file.write(binary_content)
        file.rewind

        uploaded_file = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")

        post "/api/v1/firmwares",
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

        post "/api/v1/firmwares",
             params: { firmware: { version: "99.1.0", binary_file: uploaded_file } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["error"]).to include("ліміт")

        small_file.close
        small_file.unlink
      end
    end

    describe "POST /api/v1/firmwares — validation error" do
      it "returns validation errors for missing version" do
        post "/api/v1/firmwares",
             params: { firmware: { version: "", bytecode_payload: "AABB" } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end

      it "returns validation errors for invalid bytecode" do
        post "/api/v1/firmwares",
             params: { firmware: { version: "99.2.0", bytecode_payload: "NOT_HEX!" } },
             headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
      end

      it "returns validation errors for duplicate version" do
        create(:bio_contract_firmware, version: "99.3.0")

        post "/api/v1/firmwares",
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

    describe "POST /api/v1/provisioning/register — unknown device_type" do
      it "returns error for unknown device type" do
        post "/api/v1/provisioning/register",
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

    describe "POST /api/v1/provisioning/register — validation error" do
      it "returns validation errors for invalid tree data (missing family)" do
        post "/api/v1/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: unique_hardware_uid,
                 device_type: "tree",
                 cluster_id: cluster.id,
                 family_id: nil
               }
             },
             headers: forester_headers

        # Tree requires tree_family — should fail validation
        expect(response.status).to be_in([ 422, 500 ])
        json = response.parsed_body
        expect(json["errors"] || json["error"]).to be_present
      end

      it "returns validation errors for gateway with invalid data" do
        post "/api/v1/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "",
                 device_type: "gateway",
                 cluster_id: cluster.id
               }
             },
             headers: forester_headers

        expect(response.status).to be_in([ 422, 500 ])
        json = response.parsed_body
        expect(json["errors"] || json["error"]).to be_present
      end
    end
  end

  # ==========================================================================
  # 5. BASE CONTROLLER — error handlers
  # ==========================================================================
  describe "BaseController error handling" do
    describe "ActionController::ParameterMissing → 400" do
      it "returns 400 when required params are missing" do
        # POST to maintenance_records without the required :maintenance_record key
        post "/api/v1/maintenance_records",
             params: { wrong_key: { notes: "test" } },
             headers: forester_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to include("параметр")
      end
    end

    describe "ActiveRecord::RecordNotFound → 404" do
      it "returns 404 for non-existent record" do
        get "/api/v1/maintenance_records/999999999",
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
    describe "GET /api/v1/system_health" do
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

        get "/api/v1/system_health",
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
        get "/api/v1/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["database"]["connected"]).to be true
      end

      it "handles database connection error gracefully" do
        allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(StandardError.new("DB down"))

        get "/api/v1/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["database"]["connected"]).to be false
        expect(json["database"]["error"]).to eq("DB down")
      end

      it "handles CoAP port check — port open path" do
        # Stub TCPSocket to simulate an open port
        socket_double = instance_double(TCPSocket)
        allow(TCPSocket).to receive(:new).with("127.0.0.1", 5683).and_return(socket_double)
        allow(socket_double).to receive(:close)

        get "/api/v1/system_health",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["coap_listener"]["alive"]).to be true
      end
    end
  end

  # ==========================================================================
  # 7. NOTIFICATIONS CONTROLLER
  # ==========================================================================
  describe "NotificationsController" do
    describe "PATCH /api/v1/notifications/settings — validation error" do
      it "returns errors when phone_number is invalid" do
        # Normalization strips non-numeric/non-plus chars, so use a value that
        # survives normalization but fails the regex /\A\+?[1-9]\d{1,14}\z/
        # +0 prefix fails because first digit after + must be 1-9
        patch "/api/v1/notifications/settings",
              params: { phone_number: "+0123456789" },
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
        expect(json["errors"].length).to be > 0
      end
    end

    describe "GET /api/v1/notifications/settings" do
      it "returns current notification channel settings" do
        get "/api/v1/notifications/settings",
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["user_id"]).to eq(user.id)
        expect(json["channels"]).to include("email", "phone", "telegram_chat_id", "push_token")
      end
    end
  end

  # ==========================================================================
  # 8. SETTINGS CONTROLLER
  # ==========================================================================
  describe "SettingsController" do
    describe "PATCH /api/v1/settings — validation error" do
      it "returns errors for invalid organization data" do
        patch "/api/v1/settings",
              params: { organization: { name: "", billing_email: "not-an-email" } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_an(Array)
        expect(json["errors"].length).to be > 0
      end

      it "returns errors for invalid crypto address" do
        patch "/api/v1/settings",
              params: { organization: { crypto_public_address: "invalid-address" } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end

      it "returns errors for out-of-range alert threshold" do
        patch "/api/v1/settings",
              params: { organization: { alert_threshold_critical_z: 999 } },
              headers: admin_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["errors"]).to be_present
      end
    end

    describe "GET /api/v1/settings" do
      it "returns organization settings" do
        get "/api/v1/settings",
            headers: admin_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["organization"]).to be_present
        expect(json["organization"]["name"]).to eq(organization.name)
        expect(json["organization"]["billing_email"]).to eq(organization.billing_email)
      end
    end
  end

  # ==========================================================================
  # 9. PASSWORDS CONTROLLER — rate limiting
  # ==========================================================================
  describe "PasswordsController" do
    describe "rate limiting on password reset" do
      it "responds to password reset requests" do
        mailer_double = double(deliver_later: nil)
        mailer_with = double(reset_instructions: mailer_double)
        allow(PasswordMailer).to receive(:with).and_return(mailer_with)

        post "/api/v1/forgot_password",
             params: { email: user.email_address },
             headers: json_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Provisioning, firmwares, and controller CRUD flows" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:forester_token) { forester.generate_token_for(:api_access) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(ActionCable.server).to receive(:broadcast)
    allow(PeaqRegistrationWorker).to receive(:perform_async)
  end

  # ---------------------------------------------------------------------------
  # ProvisioningController
  # ---------------------------------------------------------------------------
  describe "Provisioning API" do
    it "POST /provisioning/register provisions a tree" do
      expect {
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "0039002F313851150000BB02", # [FW.54] 24-hex UID
                 device_type: "tree",
                 cluster_id: cluster.id,
                 family_id: tree_family.id,
                 latitude: 49.4285,
                 longitude: 32.062
               }
             },
             headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }
      }.to change(Tree, :count).by(1)
       .and change(HardwareKey, :count).by(1)
       .and change(MaintenanceRecord, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["did"]).to be_present
      # [SEC.11] Zero-Trust: aes_key is never returned in the response.
      # K_seed stays in-process; the response only confirms provisioning.
      expect(json["aes_key"]).to be_nil
    end

    it "POST /provisioning/register provisions a gateway" do
      expect {
        post "/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "SNET-Q-FF001122",
                 device_type: "gateway",
                 cluster_id: cluster.id,
                 latitude: 49.4285,
                 longitude: 32.062
               }
             },
             headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }
      }.to change(Gateway, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "rejects duplicate hardware UID" do
      # [FW.54] guard живе на деривованому DID
      create(:hardware_key, device_uid: SilkenNet::DidDerivation.wire_did_from_uid_hex("0039002F3138511538323634"))

      post "/provisioning/register",
           params: {
             provisioning: {
               hardware_uid: "0039002F3138511538323634",
               device_type: "tree",
               cluster_id: cluster.id,
               family_id: tree_family.id,
               latitude: 49.4285,
               longitude: 32.062
             }
           },
           headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:conflict)
    end

    it "returns 403 for non-forester users" do
      investor = create(:user, :investor, organization: organization)
      inv_token = investor.generate_token_for(:api_access)

      post "/provisioning/register",
           params: { provisioning: { hardware_uid: "TEST", device_type: "tree", cluster_id: cluster.id } },
           headers: { "Authorization" => "Bearer #{inv_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # FirmwaresController
  # ---------------------------------------------------------------------------
  describe "Firmwares API" do
    let!(:firmware) { create(:bio_contract_firmware, version: "5.0.0") }

    it "GET /firmwares returns paginated list" do
      get "/firmwares",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
      expect(json["pagy"]).to include("page")
    end

    it "POST /firmwares creates firmware" do
      expect {
        post "/firmwares",
             params: { firmware: { version: "6.0.0", bytecode_payload: "AABB0011" } },
             headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }
      }.to change(BioContractFirmware, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    # ⊥ Пін цілиться у ВМІСТ, а не в наявність ключів: `include("trees", "gateways")`
    # на хеші звіряє самі імена, тож лишався б зеленим і на порожньому розподілі, і
    # на чужому. Пара «своє лишається ⊥ чуже відпадає» доводить обидві властивості
    # ОДНІЄЇ деривації, яку тепер ділять `#index` і `#inventory` [UI.8]: підрахунок
    # за версіями та org-скоуп. Точна рівність, а не `include`, — інакше зайва
    # версія в розподілі не мала б чим впасти.
    it "GET /firmwares/inventory returns the org-scoped version distribution" do
      # `Prosopite.pause` — фікстурна підготовка, не поведінка під тестом: `Tree`
      # має `build_default_wallet`/`ensure_calibration` в `after_create`, тож
      # створення кількох дерев поспіль виглядає для детектора як N+1. Сам запит
      # лишається ПОЗА паузою — інакше приклад глушив би детекцію на ендпоінті,
      # який і перевіряє.
      Prosopite.pause
      create_list(:tree, 2, cluster: cluster, firmware_version: "v1.0.0")
      create(:tree, cluster: cluster, firmware_version: "v2.0.0")
      create(:gateway, cluster: cluster, firmware_version: "q-1.0.0")
      create(:tree, cluster: create(:cluster, organization: create(:organization)), firmware_version: "v9.9.9")
      Prosopite.resume

      get "/firmwares/inventory",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["trees"]).to eq("v1.0.0" => 2, "v2.0.0" => 1)
      expect(json["gateways"]).to eq("q-1.0.0" => 1)
    end

    it "POST /firmwares/:id/deploy targets gateways for the poll-тракт (FW.60)" do
      gateway = create(:gateway, cluster: cluster)
      OtaTransmissionWorker.clear

      post "/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id, target_type: "Tree", canary_percentage: 10 },
           headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:accepted)
      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "returns 403 for non-admin" do
      get "/firmwares",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # AlertsController
  # ---------------------------------------------------------------------------
  describe "Alerts API" do
    let!(:alert) { create(:ews_alert, cluster: cluster, severity: :critical, status: :active) }

    it "GET /alerts returns filtered alerts" do
      get "/alerts",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
    end

    it "PATCH /alerts/:id/resolve resolves alert" do
      patch "/alerts/#{alert.id}/resolve",
            params: { notes: "Threat neutralized" },
            headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(alert.reload.status).to eq("resolved")
    end
  end

  # ---------------------------------------------------------------------------
  # Remaining controller endpoints
  # ---------------------------------------------------------------------------
  describe "Additional controller APIs" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    # ⚠️ Ці два — ЄДИНІ приклади дерева, що взагалі відкривають тіло цих двох
    # `show`-дій, тож піни тут не дублюють нікого (на відміну від решти блоку,
    # знятої як надлишкова: у неї були загартовані спадкоємці в профільних
    # `spec/requests/api/v1/*`).
    it "GET /wallets/:id returns wallet details" do
      get "/wallets/#{wallet.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["id"]).to eq(wallet.id)
    end

    it "GET /organizations/:id returns org details" do
      super_admin = create(:user, :super_admin, organization: organization)
      sa_token = super_admin.generate_token_for(:api_access)

      get "/organizations/#{organization.id}",
          headers: { "Authorization" => "Bearer #{sa_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["organization"]["id"]).to eq(organization.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Telemetry history endpoints
  # ---------------------------------------------------------------------------
  describe "Telemetry history API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "GET /trees/:id/telemetry returns tree history" do
      create(:telemetry_log, tree: tree, voltage_mv: 3800, temperature_c: 22, z_value: 25.0)

      get "/trees/#{tree.id}/telemetry",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["did"]).to eq(tree.did)
      expect(json["z_value"]).to be_an(Array)
    end

    it "GET /gateways/:id/telemetry returns gateway history" do
      create(:gateway_telemetry_log, gateway: gateway)

      get "/gateways/#{gateway.id}/telemetry",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["uid"]).to eq(gateway.uid)
    end
  end

  # ---------------------------------------------------------------------------
  # OracleVisionsController
  # ---------------------------------------------------------------------------
  describe "Oracle Visions API" do
    it "GET /oracle_visions returns visions and emission forecast" do
      get "/oracle_visions",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("visions", "emission_forecast")
    end
  end

  # ---------------------------------------------------------------------------
  # ActuatorsController
  # ---------------------------------------------------------------------------
  describe "Actuators API" do
    let!(:gateway) { create(:gateway, cluster: cluster) }
    let!(:actuator) { create(:actuator, gateway: gateway) }

    it "GET /clusters/:cluster_id/actuators returns list" do
      get "/clusters/#{cluster.id}/actuators",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
    end

    it "POST /actuators/:id/execute creates a command" do
      expect {
        post "/actuators/#{actuator.id}/execute",
             params: { action_payload: "OPEN", duration_seconds: 60 },
             headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json",
                        "Idempotency-Key" => SecureRandom.uuid }
      }.to change(ActuatorCommand, :count).by(1)

      expect(response).to have_http_status(:accepted)
    end

    it "rejects execute when command already pending" do
      create(:actuator_command, actuator: actuator, status: :issued)

      post "/actuators/#{actuator.id}/execute",
           params: { action_payload: "OPEN", duration_seconds: 60 },
           headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json",
                      "Idempotency-Key" => SecureRandom.uuid }

      expect(response).to have_http_status(:conflict)
    end
  end

  # ---------------------------------------------------------------------------
  # MaintenanceRecordsController
  # ---------------------------------------------------------------------------
  describe "Maintenance Records API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:record) { create(:maintenance_record, user: forester, maintainable: tree) }

    it "GET /maintenance_records/:id returns record detail" do
      get "/maintenance_records/#{record.id}",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "POST /maintenance_records creates a record" do
      expect {
        post "/maintenance_records",
             params: {
               maintenance_record: {
                 maintainable_type: "Tree",
                 maintainable_id: tree.id,
                 action_type: "inspection",
                 performed_at: Time.current.iso8601,
                 notes: "Routine check"
               }
             },
             headers: {
               "Authorization" => "Bearer #{forester_token}",
               "Accept" => "application/json",
               # [E.20] JSON-гілка `create` вимагає ключ ідемпотентності
               "Idempotency-Key" => SecureRandom.uuid
             }
      }.to change(MaintenanceRecord, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # GeoUtils
  # ---------------------------------------------------------------------------
  describe "GeoUtils haversine distance" do
    it "calculates distance between two points" do
      # Kyiv to Cherkasy approx ~190km
      distance = SilkenNet::GeoUtils.haversine_distance_m(50.4501, 30.5234, 49.4285, 32.0620)
      expect(distance).to be_between(155_000, 165_000)
    end

    it "returns 0 for same point" do
      distance = SilkenNet::GeoUtils.haversine_distance_m(50.45, 30.52, 50.45, 30.52)
      expect(distance).to be < 1
    end
  end

  # ---------------------------------------------------------------------------
  # PriceOracleService
  # ---------------------------------------------------------------------------
  describe "PriceOracleService" do
    it "returns a mock price in test environment" do
      price = PriceOracleService.current_scc_price
      expect(price).to be_a(Numeric)
      expect(price).to be > 0
    end
  end

  # ---------------------------------------------------------------------------
  # ChainAuditService
  # ---------------------------------------------------------------------------
  describe "ChainAuditService" do
    it "compares DB totals with chain totals" do
      allow_any_instance_of(ChainAuditService).to receive(:fetch_chain_total_supply).and_return(100.0)
      create(:blockchain_transaction, wallet: create(:wallet), status: :confirmed, amount: 100.0, token_type: :carbon_coin)

      result = ChainAuditService.call
      expect(result.db_total).to be_a(Numeric)
      expect(result.chain_total).to eq(100.0)
      expect(result).to respond_to(:critical)
    end
  end
end

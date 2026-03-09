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
  end

  # ---------------------------------------------------------------------------
  # ProvisioningController
  # ---------------------------------------------------------------------------
  describe "Provisioning API" do
    it "POST /api/v1/provisioning/register provisions a tree" do
      expect {
        post "/api/v1/provisioning/register",
             params: {
               provisioning: {
                 hardware_uid: "ABCDEF1234567890",
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
      expect(json["aes_key"]).to be_present
    end

    it "POST /api/v1/provisioning/register provisions a gateway" do
      expect {
        post "/api/v1/provisioning/register",
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
      create(:hardware_key, device_uid: "DUPLICATE-UID-001")

      post "/api/v1/provisioning/register",
           params: {
             provisioning: {
               hardware_uid: "DUPLICATE-UID-001",
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

      post "/api/v1/provisioning/register",
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

    it "GET /api/v1/firmwares returns paginated list" do
      get "/api/v1/firmwares",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
      expect(json["pagy"]).to include("page")
    end

    it "POST /api/v1/firmwares creates firmware" do
      expect {
        post "/api/v1/firmwares",
             params: { firmware: { version: "6.0.0", bytecode_payload: "AABB0011" } },
             headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }
      }.to change(BioContractFirmware, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "GET /api/v1/firmwares/inventory returns distribution" do
      get "/api/v1/firmwares/inventory",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("trees", "gateways")
    end

    it "POST /api/v1/firmwares/:id/deploy queues OTA transmission" do
      expect(OtaTransmissionWorker).to receive(:perform_async)

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id, target_type: "Tree", canary_percentage: 10 },
           headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:accepted)
    end

    it "returns 403 for non-admin" do
      get "/api/v1/firmwares",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # AlertsController
  # ---------------------------------------------------------------------------
  describe "Alerts API" do
    let!(:alert) { create(:ews_alert, cluster: cluster, severity: :critical, status: :active) }

    it "GET /api/v1/alerts returns filtered alerts" do
      get "/api/v1/alerts",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
    end

    it "PATCH /api/v1/alerts/:id/resolve resolves alert" do
      patch "/api/v1/alerts/#{alert.id}/resolve",
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
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "GET /api/v1/clusters returns clusters" do
      get "/api/v1/clusters",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/clusters/:id returns cluster details" do
      get "/api/v1/clusters/#{cluster.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/trees/:id returns tree" do
      get "/api/v1/trees/#{tree.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/gateways returns gateways" do
      get "/api/v1/gateways",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/gateways/:id returns gateway" do
      get "/api/v1/gateways/#{gateway.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/wallets returns wallets" do
      get "/api/v1/wallets",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/wallets/:id returns wallet details" do
      get "/api/v1/wallets/#{wallet.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/organizations returns organizations" do
      super_admin = create(:user, :super_admin, organization: organization)
      sa_token = super_admin.generate_token_for(:api_access)

      get "/api/v1/organizations",
          headers: { "Authorization" => "Bearer #{sa_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/organizations/:id returns org details" do
      super_admin = create(:user, :super_admin, organization: organization)
      sa_token = super_admin.generate_token_for(:api_access)

      get "/api/v1/organizations/#{organization.id}",
          headers: { "Authorization" => "Bearer #{sa_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/blockchain_transactions returns transactions" do
      create(:blockchain_transaction, wallet: wallet)

      get "/api/v1/blockchain_transactions",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/audit_logs returns logs" do
      create(:audit_log, user: admin, organization: organization)

      get "/api/v1/audit_logs",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/system_audits returns chain audit data" do
      allow(ChainAuditService).to receive(:call).and_return(
        ChainAuditService::Result.new(
          db_total: 100.0, chain_total: 100.0, delta: 0.0,
          critical: false, checked_at: Time.current
        )
      )

      get "/api/v1/system_audits",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Telemetry history endpoints
  # ---------------------------------------------------------------------------
  describe "Telemetry history API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "GET /api/v1/trees/:id/telemetry returns tree history" do
      create(:telemetry_log, tree: tree, voltage_mv: 3800, temperature_c: 22, z_value: 25.0)

      get "/api/v1/trees/#{tree.id}/telemetry",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["did"]).to eq(tree.did)
      expect(json["impedance"]).to be_an(Array)
    end

    it "GET /api/v1/gateways/:id/telemetry returns gateway history" do
      create(:gateway_telemetry_log, gateway: gateway)

      get "/api/v1/gateways/#{gateway.id}/telemetry",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["uid"]).to eq(gateway.uid)
    end
  end

  # ---------------------------------------------------------------------------
  # TreeFamiliesController
  # ---------------------------------------------------------------------------
  describe "Tree Families API" do
    it "GET /api/v1/tree_families returns families" do
      get "/api/v1/tree_families",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/tree_families/:id returns family" do
      get "/api/v1/tree_families/#{tree_family.id}",
          headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # OracleVisionsController
  # ---------------------------------------------------------------------------
  describe "Oracle Visions API" do
    it "GET /api/v1/oracle_visions returns visions and yield forecast" do
      get "/api/v1/oracle_visions",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("visions", "yield_forecast")
    end

    it "GET /api/v1/oracle_visions/stream_config returns config" do
      get "/api/v1/oracle_visions/stream_config",
          params: { cluster_id: cluster.id },
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["stream_name"]).to include(cluster.id.to_s)
    end
  end

  # ---------------------------------------------------------------------------
  # ActuatorsController
  # ---------------------------------------------------------------------------
  describe "Actuators API" do
    let!(:gateway) { create(:gateway, cluster: cluster) }
    let!(:actuator) { create(:actuator, gateway: gateway) }

    it "GET /api/v1/clusters/:cluster_id/actuators returns list" do
      get "/api/v1/clusters/#{cluster.id}/actuators",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]).to be_an(Array)
    end

    it "GET /api/v1/actuators/:id returns actuator detail" do
      get "/api/v1/actuators/#{actuator.id}",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "POST /api/v1/actuators/:id/execute creates a command" do
      expect {
        post "/api/v1/actuators/#{actuator.id}/execute",
             params: { action_payload: "OPEN", duration_seconds: 60 },
             headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }
      }.to change(ActuatorCommand, :count).by(1)

      expect(response).to have_http_status(:accepted)
    end

    it "rejects execute when command already pending" do
      create(:actuator_command, actuator: actuator, status: :issued)

      post "/api/v1/actuators/#{actuator.id}/execute",
           params: { action_payload: "OPEN", duration_seconds: 60 },
           headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:conflict)
    end
  end

  # ---------------------------------------------------------------------------
  # MaintenanceRecordsController
  # ---------------------------------------------------------------------------
  describe "Maintenance Records API" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:record) { create(:maintenance_record, user: forester, maintainable: tree) }

    it "GET /api/v1/maintenance_records returns records" do
      get "/api/v1/maintenance_records",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/maintenance_records/:id returns record detail" do
      get "/api/v1/maintenance_records/#{record.id}",
          headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "POST /api/v1/maintenance_records creates a record" do
      expect {
        post "/api/v1/maintenance_records",
             params: {
               maintenance_record: {
                 maintainable_type: "Tree",
                 maintainable_id: tree.id,
                 action_type: "inspection",
                 performed_at: Time.current.iso8601,
                 notes: "Routine check"
               }
             },
             headers: { "Authorization" => "Bearer #{forester_token}", "Accept" => "application/json" }
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

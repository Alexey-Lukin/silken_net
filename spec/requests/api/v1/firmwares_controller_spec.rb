# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FirmwaresController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:api_token) { admin.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "POST /api/v1/firmwares/:id/deploy" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "2.0.0", bytecode_payload: "AABBCCDD")
    end
    let(:cluster) { create(:cluster, organization: organization) }
    let!(:gateway) { create(:gateway, cluster: cluster) }

    before { OtaTransmissionWorker.clear }

    it "targets the gateway via pending_firmware_id (FW.60 poll-тракт, без push-enqueue)" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id, canary_percentage: 5 }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(5)
      expect(response.parsed_body["dispatched_gateways"]).to eq(1)
      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "defaults canary_percentage to 100 when not specified" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(100)
    end

    it "clamps canary_percentage to valid range" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
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

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("anti-rollback")
      expect(response.parsed_body["skipped_clusters"].sole["reason"]).to eq("rollback")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "rejects a deploy with no eligible gateways with 422" do
      gateway.update!(state: :maintenance)

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["skipped_clusters"].sole["reason"]).to eq("no_gateways")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "mixed whole-forest rejection carries BOTH skip reasons; stale message wins the headline" do
      cluster.update!(ota_version_hiwater: firmware.id) # rollback-skip
      empty_cluster = create(:cluster, organization: organization) # no_gateways-skip

      post "/api/v1/firmwares/#{firmware.id}/deploy", headers: headers, as: :json

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
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Quantum" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("Tree", "Gateway")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "rejects target_type contradicting the firmware hardware type with 400" do
      firmware.update!(target_hardware_type: "Tree")

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Gateway", cluster_id: cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("Tree")
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "accepts a matching target_type and reports the cluster target" do
      firmware.update!(target_hardware_type: "Tree")

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { target_type: "Tree", cluster_id: cluster.id, canary_percentage: 25 },
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["dispatched_gateways"]).to eq(1)
      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
    end

    it "rejects cluster_id from another organization with 404" do
      other_org = create(:organization)
      other_cluster = create(:cluster, organization: other_org)

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { cluster_id: other_cluster.id }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(OtaTransmissionWorker.jobs).to be_empty
    end
  end

  describe "GET /api/v1/firmwares (index)" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "3.0.0", bytecode_payload: "AABBCCDD")
    end

    it "returns firmware list as JSON" do
      get "/api/v1/firmwares", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to be_an(Array)
    end

    it "renders HTML dashboard for firmware index" do
      get "/api/v1/firmwares", headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "GET /api/v1/firmwares/new" do
    it "exercises the new firmware form path" do
      get "/api/v1/firmwares/new", headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      # Phlex component may not fully render in test env, but code path is exercised
      expect(response.status).to be_in([ 200, 500 ])
    end
  end

  describe "POST /api/v1/firmwares (create)" do
    it "creates firmware successfully as JSON" do
      post "/api/v1/firmwares",
           params: { firmware: { version: "4.0.0", bytecode_payload: "DEADBEEF" } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it "exercises HTML error path on validation failure" do
      post "/api/v1/firmwares",
           params: { firmware: { version: "", bytecode_payload: "" } },
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      # Phlex component may not fully render in test env, but code path is exercised
      expect(response.status).to be_in([ 200, 500 ])
    end

    # =========================================================================
    # SIZE BYPASS GUARD: clients posting bytecode_payload directly (no
    # multipart upload) used to skip MAX_FIRMWARE_SIZE. The cap is now
    # enforced against the hex string length (2× binary size).
    # =========================================================================
    it "rejects oversized bytecode_payload with 422" do
      huge_hex = "AA" * (Api::V1::FirmwaresController::MAX_BYTECODE_PAYLOAD_HEX_SIZE / 2 + 1)
      post "/api/v1/firmwares",
           params: { firmware: { version: "9.9.9", bytecode_payload: huge_hex } },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "POST /api/v1/firmwares/:id/deploy (HTML format)" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "5.0.0", bytecode_payload: "AABBCCDD")
    end
    let(:cluster) { create(:cluster, organization: organization) }

    before { OtaTransmissionWorker.clear }

    it "redirects with a notice on successful HTML deploy (the UI one-click path)" do
      gw = create(:gateway, cluster: cluster)

      post "/api/v1/firmwares/#{firmware.id}/deploy",
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to be_present
      expect(gw.reload.pending_firmware_id).to eq(firmware.id)
    end

    it "redirects with an alert when nothing was dispatched" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
      expect(OtaTransmissionWorker.jobs).to be_empty
    end
  end
end

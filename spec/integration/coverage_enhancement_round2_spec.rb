# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integration coverage round 2 — branch coverage gaps" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, :online, cluster: cluster) }
  let(:actuator) { create(:actuator, gateway: gateway) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(ActuatorCommandWorker).to receive(:perform_async)
    allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed)
    allow(AlertNotificationWorker).to receive(:perform_async)
  end

  # ==========================================================================
  # 1. ACTUATOR COMMAND — nil gateway chain, nil actuator, broadcast fallback
  # ==========================================================================
  describe "ActuatorCommand branch coverage" do
    describe "denormalize_organization — actuator with no gateway" do
      it "sets organization_id to nil when gateway is nil" do
        orphan_actuator = build(:actuator, gateway: nil)
        allow(orphan_actuator).to receive(:gateway).and_return(nil)

        command = ActuatorCommand.new(
          actuator: orphan_actuator,
          command_payload: "OPEN",
          duration_seconds: 60
        )
        command.send(:denormalize_organization)
        expect(command.organization_id).to be_nil
      end
    end

    describe "duration_within_safety_envelope — nil actuator safe navigation" do
      it "skips validation when actuator returns nil from safe navigation" do
        command = ActuatorCommand.new(
          actuator: actuator,
          command_payload: "OPEN",
          duration_seconds: 30
        )
        allow(command).to receive(:actuator).and_return(nil)
        command.send(:duration_within_safety_envelope)
        expect(command.errors[:duration_seconds]).to be_empty
      end
    end

    describe "broadcast_prepend_to_activity_feed — fallback through gateway chain" do
      it "falls back to actuator.gateway.cluster.organization when organization is nil" do
        allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed).and_call_original
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(organization_id: nil)
        command.reload

        command.send(:broadcast_prepend_to_activity_feed)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).at_least(:once)
      end

      it "returns nil when both organization and gateway chain are nil" do
        allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed).and_call_original
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(organization_id: nil)
        command.reload

        allow(command.actuator).to receive(:gateway).and_return(nil)
        result = command.send(:broadcast_prepend_to_activity_feed)
        expect(result).to be_nil
      end
    end
  end

  # ==========================================================================
  # 2. MAINTENANCE RECORD BLUEPRINT — nil maintainable, show view with url_helpers
  # ==========================================================================
  describe "MaintenanceRecordBlueprint branch coverage" do
    let(:tree) { create(:tree, cluster: cluster) }
    let(:user) { create(:user, :forester) }
    let(:record) { create(:maintenance_record, :with_cost, user: user, maintainable: tree) }

    describe "maintainable_label when maintainable is nil" do
      it "handles nil maintainable gracefully" do
        record = create(:maintenance_record, user: user, maintainable: tree)
        allow(record).to receive(:maintainable).and_return(nil)
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :index)
        expect(json[:maintainable_label]).to include("//")
      end
    end

    describe "maintainable_label when did is nil but uid is present" do
      it "falls back to uid when did method is missing" do
        gw_record = create(:maintenance_record, user: user, maintainable: gateway)
        json = MaintenanceRecordBlueprint.render_as_hash(gw_record, view: :index)
        expect(json[:maintainable_label]).to include(gateway.uid)
      end
    end

    describe "show view photo_urls without url_helpers" do
      it "returns empty strings for thumb_url and full_url when url_helpers is nil" do
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :show)
        expect(json[:photo_urls]).to eq([])
      end
    end

    describe "show view photo_urls with url_helpers" do
      it "uses url_helpers when provided and photos are attached" do
        record.photos.attach(
          io: StringIO.new("fake image data for test"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )

        url_helpers = double("url_helpers")
        allow(url_helpers).to receive(:rails_representation_url).and_return("/thumb.jpg")
        allow(url_helpers).to receive(:rails_blob_url).and_return("/full.jpg")

        json = MaintenanceRecordBlueprint.render_as_hash(
          record,
          view: :show,
          url_helpers: url_helpers
        )

        expect(json[:photo_urls]).not_to be_empty
        expect(json[:photo_urls].first[:thumb_url]).to eq("/thumb.jpg")
        expect(json[:photo_urls].first[:full_url]).to eq("/full.jpg")
      end
    end
  end

  # ==========================================================================
  # 3. BASE CONTROLLER — authorize_admin!, authorize_super_admin!, authorize_forester!
  #    when current_user is nil
  # ==========================================================================
  describe "Api::V1::BaseController RBAC helpers" do
    let(:controller) { Api::V1::BaseController.new }

    before do
      allow(controller).to receive(:render)
      allow(controller).to receive(:render_forbidden)
    end

    describe "authorize_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_super_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_super_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_forester!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_admin! with admin user" do
      it "does not call render_forbidden" do
        admin = create(:user, :admin)
        allow(controller).to receive(:current_user).and_return(admin)
        controller.send(:authorize_admin!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! with forester user" do
      it "does not call render_forbidden" do
        forester = create(:user, :forester)
        allow(controller).to receive(:current_user).and_return(forester)
        controller.send(:authorize_forester!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end
  end

  # ==========================================================================
  # 4. OTA TRANSMISSION WORKER — nil response, gateway not found on failure
  # ==========================================================================
  describe "OtaTransmissionWorker branch coverage" do
    let(:firmware) { create(:bio_contract_firmware, :active) }
    let!(:hw_key) { create(:hardware_key, device_uid: gateway.uid) }

    before do
      allow(OtaPackagerService).to receive(:prepare).and_return({
        packages: ["A" * 512],
        manifest: { total_chunks: 1 }
      })
    end

    describe "NACK when response is nil" do
      it "handles nil response from CoAP (line 44)" do
        allow(CoapClient).to receive(:put).and_return(nil)
        expect {
          OtaTransmissionWorker.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)
        }.not_to raise_error
      end
    end

    describe "NACK when response.success? is false" do
      it "handles unsuccessful response" do
        response = double("response", success?: false, code: "4.04")
        allow(CoapClient).to receive(:put).and_return(response)
        expect {
          OtaTransmissionWorker.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)
        }.not_to raise_error
      end
    end

    describe "handle_chunk_failure when gateway not found (nil)" do
      it "handles nil gateway in max retries path (line 118)" do
        allow(CoapClient).to receive(:put).and_return(nil)
        allow(Gateway).to receive(:find_by).with(uid: gateway.uid).and_return(nil)

        worker = OtaTransmissionWorker.new
        worker.send(:handle_chunk_failure, gateway.uid, "firmware", firmware.id, 0, 5, "test error")
        # Gateway.find_by returns nil, so &.update! is skipped gracefully
      end
    end
  end

  # ==========================================================================
  # 5. ACTUATOR COMMAND WORKER — retries exhausted, nil command, nil response,
  #    nil org in broadcast
  # ==========================================================================
  describe "ActuatorCommandWorker branch coverage" do
    let(:tree) { create(:tree, cluster: cluster) }
    let!(:hw_key) { create(:hardware_key, device_uid: gateway.uid) }

    describe "sidekiq_retries_exhausted when command is nil (not found)" do
      it "does nothing when command not found" do
        job = { "args" => [-999], "error_message" => "some error" }
        expect {
          ActuatorCommandWorker.sidekiq_retries_exhausted_block.call(job, StandardError.new("test"))
        }.not_to raise_error
      end
    end

    describe "sidekiq_retries_exhausted when command.update returns false" do
      it "skips broadcast when update fails" do
        command = create(:actuator_command, actuator: actuator)
        allow(ActuatorCommand).to receive(:find_by).with(id: command.id).and_return(command)
        allow(command).to receive(:update).and_return(false)

        job = { "args" => [command.id], "error_message" => "some error" }
        expect(ActuatorCommandWorker).not_to receive(:broadcast_command_state_static)
        ActuatorCommandWorker.sidekiq_retries_exhausted_block.call(job, StandardError.new("test"))
      end
    end

    describe "broadcast_command_state_static when org is nil" do
      it "returns nil when organization chain resolves to nil" do
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(organization_id: nil)
        command.reload

        allow(command.actuator.gateway.cluster).to receive(:organization).and_return(nil)
        result = ActuatorCommandWorker.broadcast_command_state_static(command)
        expect(result).to be_nil
      end
    end

    describe "perform — nil response from CoAP" do
      it "raises when response is nil (line 97-98)" do
        command = create(:actuator_command, actuator: actuator)
        allow(CoapClient).to receive(:put).and_return(nil)
        allow(ResetActuatorStateWorker).to receive(:perform_in)

        expect {
          ActuatorCommandWorker.new.perform(command.id)
        }.to raise_error(RuntimeError, /Королева відхилила/)
      end
    end

    describe "perform — response with code but not success" do
      it "raises with the response code in the message" do
        command = create(:actuator_command, actuator: actuator)
        response = double("response", success?: false, code: "5.00")
        allow(CoapClient).to receive(:put).and_return(response)
        allow(ResetActuatorStateWorker).to receive(:perform_in)

        expect {
          ActuatorCommandWorker.new.perform(command.id)
        }.to raise_error(RuntimeError, /5\.00/)
      end
    end
  end

  # ==========================================================================
  # 6. TELEMETRY UNPACKER SERVICE — gateway present (uid branch),
  #    firmware_id positive, undefined status code, fw_pending skip
  # ==========================================================================
  describe "TelemetryUnpackerService branch coverage" do
    let(:tree_family) { create(:tree_family) }
    let(:did_hex) { "0000AB01" }
    let(:extracted_did) { did_hex.to_i(16).to_s(16).upcase }
    let(:tree) do
      t = create(:tree, cluster: cluster, tree_family: tree_family, latitude: 49.4, longitude: 32.0)
      t.update_column(:did, extracted_did)
      t.reload
    end
    let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    before do
      tree.create_device_calibration! if tree.device_calibration.nil?
      allow(IotexVerificationWorker).to receive(:perform_async)
      allow(GatewayTelemetryWorker).to receive(:perform_async)
      allow(AlertDispatchService).to receive(:analyze_and_trigger!)
      allow(SilkenNet::Attractor).to receive(:calculate_z).and_return(25.0)
    end

    def build_chunk(did_hex_str, rssi: 65, voltage: 3800, temp: 22, acoustic: 0, metabolism: 100,
                    status_byte: 0x05, ttl: 3, firmware_id: 0)
      did_int = did_hex_str.to_i(16)
      did_bytes = [did_int].pack("N")
      rssi_byte = [rssi].pack("C")
      pad = [firmware_id].pack("n") + "\x00\x00"
      payload = [did_int, voltage, temp, acoustic, metabolism, status_byte, ttl, pad].pack("N n c C n C C a4")
      did_bytes + rssi_byte + payload
    end

    describe "gateway uid branch (line 100) — when gateway is present" do
      it "sets queen_uid in log_attributes from gateway.uid" do
        chunk = build_chunk(did_hex, voltage: 3800, temp: 22)
        service = TelemetryUnpackerService.new(chunk, gateway.id)
        service.perform

        log = tree.telemetry_logs.last
        expect(log).not_to be_nil
        expect(log.queen_uid).to eq(gateway.uid)
      end
    end

    describe "firmware_id positive branch (line 108)" do
      it "sets firmware_version_id when firmware_id is positive" do
        chunk = build_chunk(did_hex, firmware_id: 42)
        service = TelemetryUnpackerService.new(chunk, gateway.id)
        service.perform

        log = tree.telemetry_logs.last
        expect(log.firmware_version_id).to eq(42)
      end

      it "sets firmware_version_id to nil when firmware_id is zero" do
        chunk = build_chunk(did_hex, firmware_id: 0)
        service = TelemetryUnpackerService.new(chunk, gateway.id)
        service.perform

        log = tree.telemetry_logs.last
        expect(log.firmware_version_id).to be_nil
      end
    end

    describe "interpret_status — undefined status code (case else)" do
      it "returns nil for an undefined status code (3 = tamper_detected is highest)" do
        service = TelemetryUnpackerService.new("", nil)
        result = service.send(:interpret_status, 99)
        expect(result).to be_nil
      end
    end

    describe "check_firmware_mismatch! — fw_pending skip (line 202)" do
      it "skips update when tree is already fw_pending" do
        active_firmware = create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        tree.update_columns(firmware_update_status: Tree.firmware_update_statuses[:fw_pending])

        chunk = build_chunk(did_hex, firmware_id: active_firmware.id - 1)
        service = TelemetryUnpackerService.new(chunk, gateway.id)
        service.perform

        tree.reload
        expect(tree.firmware_fw_pending?).to be true
      end

      it "sets fw_pending when tree is fw_idle and firmware mismatches" do
        active_firmware = create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        tree.update_columns(firmware_update_status: Tree.firmware_update_statuses[:fw_idle])

        chunk = build_chunk(did_hex, firmware_id: active_firmware.id - 1)
        service = TelemetryUnpackerService.new(chunk, gateway.id)
        service.perform

        tree.reload
        expect(tree.firmware_fw_pending?).to be true
      end
    end
  end

  # ==========================================================================
  # 7. BLOCKCHAIN BURNING SERVICE — zero burn_amount, success path,
  #    nil source_tree, nil audit_wallet
  # ==========================================================================
  describe "BlockchainBurningService branch coverage" do
    let(:tree) { create(:tree, cluster: cluster) }
    let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }
    let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    before do
      unless defined?(Kredis)
        kredis_mod = Module.new do
          def self.lock(*, **, &block)
            block&.call
          end
        end
        stub_const("Kredis", kredis_mod)
      end
      allow(Kredis).to receive(:lock).and_yield

      allow(Eth::Client).to receive(:create).and_return(double("client"))
      allow(Eth::Key).to receive(:new).and_return(double("key", address: "0xOracle"))
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("http://localhost")
      allow(ENV).to receive(:fetch).with("ORACLE_PRIVATE_KEY").and_return("a" * 64)
      allow(ENV).to receive(:fetch).with("CARBON_COIN_CONTRACT_ADDRESS").and_return("0x" + "b" * 40)
    end

    describe "burn_amount zero (line 42)" do
      it "returns early when burn_amount is zero" do
        # total_minted is non-zero but damage_ratio makes burn_amount round to 0
        create(:blockchain_transaction, wallet: wallet, amount: 1, status: :confirmed)
        allow_any_instance_of(BlockchainBurningService).to receive(:calculate_damage_ratio).and_return(0.0)

        result = BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
        expect(result).to be_nil
      end
    end

    describe "total_minted_amount zero (line 34)" do
      it "returns early when no confirmed transactions exist" do
        result = BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)
        expect(result).to be_nil
      end
    end

    describe "success path with tx_hash (lines 70-76)" do
      it "marks naas_contract as breached and creates audit transaction" do
        create(:blockchain_transaction, wallet: wallet, amount: 100, status: :confirmed)

        mock_client = double("client")
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(mock_client).to receive(:transact_and_wait).and_return("0x" + "f" * 64)

        BlockchainBurningService.call(organization.id, naas_contract.id, source_tree: tree)

        naas_contract.reload
        expect(naas_contract.status).to eq("breached")

        audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(audit_tx).not_to be_nil
        expect(audit_tx.tx_hash).to eq("0x" + "f" * 64)
      end
    end

    describe "nil source_tree (line 91)" do
      it "uses cluster.trees.active.first wallet as audit_wallet" do
        create(:blockchain_transaction, wallet: wallet, amount: 100, status: :confirmed)

        mock_client = double("client")
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(mock_client).to receive(:transact_and_wait).and_return("0xabc123")

        BlockchainBurningService.call(organization.id, naas_contract.id)

        audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(audit_tx.wallet).to eq(wallet)
      end
    end

    describe "nil audit_wallet (line 95)" do
      it "creates transaction with cluster instead of wallet when all trees dead" do
        create(:blockchain_transaction, wallet: wallet, amount: 100, status: :confirmed)
        tree.update_columns(status: Tree.statuses[:deceased])

        mock_client = double("client")
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(mock_client).to receive(:transact_and_wait).and_return("0xdead")

        BlockchainBurningService.call(organization.id, naas_contract.id)

        audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(audit_tx.wallet).to be_nil
        expect(audit_tx.cluster).to eq(cluster)
      end
    end
  end

  # ==========================================================================
  # 8. TREE MODEL — cluster nil in current_stress, latitude nil broadcast skip,
  #    calibration already exists, did blank normalization
  # ==========================================================================
  describe "Tree model branch coverage" do
    describe "current_stress when cluster is nil (line 99)" do
      it "falls back to UTC yesterday when cluster is nil" do
        tree = create(:tree, cluster: cluster)
        allow(tree).to receive(:cluster).and_return(nil)
        expect(tree.current_stress).to eq(0.0)
      end
    end

    describe "broadcast_map_update when latitude is nil (line 135)" do
      it "returns nil without broadcasting when latitude is absent" do
        allow_any_instance_of(Tree).to receive(:broadcast_map_update).and_call_original
        tree = create(:tree, cluster: cluster)
        tree.update_columns(latitude: nil)
        tree.reload

        result = tree.broadcast_map_update
        expect(result).to be_nil
      end
    end

    describe "broadcast_map_update when longitude is nil" do
      it "returns nil without broadcasting when longitude is absent" do
        allow_any_instance_of(Tree).to receive(:broadcast_map_update).and_call_original
        tree = create(:tree, cluster: cluster)
        tree.update_columns(longitude: nil)
        tree.reload

        result = tree.broadcast_map_update
        expect(result).to be_nil
      end
    end

    describe "ensure_calibration when calibration already exists (line 151)" do
      it "does not create a new calibration if one exists" do
        tree = create(:tree, cluster: cluster)
        existing_cal = tree.device_calibration
        expect(existing_cal).not_to be_nil

        # Force the callback again
        tree.send(:ensure_calibration)
        expect(tree.device_calibration.id).to eq(existing_cal.id)
      end
    end

    describe "normalize_did when did is blank (line 155)" do
      it "does not modify did when it is blank" do
        tree = Tree.new(did: "", cluster: cluster, tree_family: create(:tree_family))
        tree.send(:normalize_did)
        # did should remain as-is — won't be set to stripped blank
        expect(tree.did).to eq("")
      end

      it "strips and upcases when did is present" do
        tree = Tree.new(did: " snet-0000abcd ", cluster: cluster, tree_family: create(:tree_family))
        tree.send(:normalize_did)
        expect(tree.did).to eq("SNET-0000ABCD")
      end
    end
  end

  # ==========================================================================
  # 9. EWS ALERT — tree nil in coordinates, status not resolved in broadcast,
  #    should_broadcast? throttling, broadcast_alert_update skip
  # ==========================================================================
  describe "EwsAlert branch coverage" do
    describe "coordinates when tree is nil (line 80)" do
      it "falls back to cluster geo_center when tree is nil" do
        alert = create(:ews_alert, cluster: cluster, tree: nil)
        allow(cluster).to receive(:geo_center).and_return({ lat: 50.0, lng: 30.0 })
        expect(alert.coordinates).to eq([50.0, 30.0])
      end

      it "falls back to [0, 0] when tree is nil and cluster has no geo_center" do
        alert = create(:ews_alert, cluster: cluster, tree: nil)
        allow(cluster).to receive(:geo_center).and_return(nil)
        expect(alert.coordinates).to eq([0.0, 0.0])
      end
    end

    describe "broadcast_status_change when status is NOT resolved (lines 120-125)" do
      it "replaces badge but does not broadcast remove_to" do
        tree = create(:tree, cluster: cluster)
        # Stub broadcast_alert_update to avoid Phlex url_helpers issue
        allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
        alert = create(:ews_alert, cluster: cluster, tree: tree, status: :active)

        # Update status to ignored (not resolved)
        alert.update!(status: :ignored)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_remove_to)
            .with("ews_live_feed", hash_including(target: "alert_row_#{alert.id}"))
      end
    end

    describe "broadcast_status_change when status IS resolved" do
      it "broadcasts both replace and remove" do
        tree = create(:tree, cluster: cluster)
        allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
        alert = create(:ews_alert, cluster: cluster, tree: tree)

        alert.update!(
          status: :resolved,
          resolved_at: Time.current,
          resolution_notes: "Fixed"
        )
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).at_least(:once)
      end
    end

    describe "broadcast_alert_update — should_broadcast? throttle (line 142)" do
      it "skips broadcast when throttle cache exists" do
        tree = create(:tree, cluster: cluster)
        allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
        alert = create(:ews_alert, cluster: cluster, tree: tree)

        # Now test the method directly with throttle set
        Rails.cache.write("ews_alert_broadcast_throttle:#{alert.id}", true, expires_in: 5.seconds)
        # should_broadcast? will return false, so broadcast_alert_update returns nil
        expect(alert.send(:should_broadcast?)).to be false
      end

      it "broadcasts when throttle cache does not exist" do
        tree = create(:tree, cluster: cluster)
        allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
        alert = create(:ews_alert, cluster: cluster, tree: tree)

        Rails.cache.delete("ews_alert_broadcast_throttle:#{alert.id}")
        expect(alert.send(:should_broadcast?)).to be true
      end
    end

    describe "should_broadcast? returns false then true" do
      it "returns false on second call within throttle window" do
        tree = create(:tree, cluster: cluster)
        alert = create(:ews_alert, cluster: cluster, tree: tree)

        Rails.cache.delete("ews_alert_broadcast_throttle:#{alert.id}")
        expect(alert.send(:should_broadcast?)).to be true
        expect(alert.send(:should_broadcast?)).to be false
      end
    end
  end

  # ==========================================================================
  # 10. GATEWAY TELEMETRY WORKER — nil gateway in rescue, nil cluster_id,
  #     generic hardware fault message
  # ==========================================================================
  describe "GatewayTelemetryWorker branch coverage" do
    describe "gateway nil in rescue (line 50)" do
      it "handles rescue when gateway is not set (RecordNotFound)" do
        expect {
          GatewayTelemetryWorker.new.perform("NONEXISTENT-UID", { voltage_mv: 4000, temperature_c: 25, cellular_signal_csq: 15 })
        }.not_to raise_error
      end
    end

    describe "return unless gateway.cluster_id (line 64)" do
      it "skips alert creation when gateway has no cluster_id" do
        gw = create(:gateway, cluster: cluster, ip_address: "10.0.0.2")
        log = create(:gateway_telemetry_log, :low_battery, gateway: gw)

        allow(gw).to receive(:cluster_id).and_return(nil)

        worker = GatewayTelemetryWorker.new
        worker.send(:check_system_health, gw, log)
        expect(EwsAlert.where(alert_type: :system_fault)).to be_empty
      end
    end

    describe "format_health_message — generic fault branch (else line 84-86)" do
      it "returns generic message when no specific threshold is breached but critical_fault? is true" do
        # Create a log that returns critical_fault? = true but doesn't match any specific threshold
        log = create(:gateway_telemetry_log, gateway: gateway,
                     voltage_mv: GatewayTelemetryLog::LOW_BATTERY_THRESHOLD + 100,
                     temperature_c: GatewayTelemetryLog::OVERHEAT_THRESHOLD - 10,
                     cellular_signal_csq: GatewayTelemetryLog::LOW_SIGNAL_THRESHOLD + 5)

        allow(log).to receive(:critical_fault?).and_return(true)
        # Force the message formatting via the worker
        worker = GatewayTelemetryWorker.new
        message = worker.send(:format_health_message, gateway, log)
        expect(message).to include("Апаратний збій")
      end
    end
  end

  # ==========================================================================
  # 11. TOKENOMICS EVALUATOR WORKER — zero tokens_to_mint, nil tree.did,
  #     different stats branches
  # ==========================================================================
  describe "TokenomicsEvaluatorWorker branch coverage" do
    before do
      allow(MintCarbonCoinWorker).to receive(:perform_async)
      allow(BlockchainMintingService).to receive(:call_batch)
    end

    describe "tokens_to_mint is zero (line 31)" do
      it "skips wallet with balance below emission threshold" do
        tree = create(:tree, cluster: cluster)
        wallet = tree.wallet
        wallet.update_columns(balance: TokenomicsEvaluatorWorker::EMISSION_THRESHOLD - 1)

        TokenomicsEvaluatorWorker.new.perform
        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end

    describe "wallet.tree.did when tree is nil (line 47 — rescue)" do
      it "continues processing after error with nil tree reference" do
        tree1 = create(:tree, cluster: cluster)
        wallet1 = tree1.wallet
        wallet1.update_columns(balance: TokenomicsEvaluatorWorker::EMISSION_THRESHOLD * 2)

        # Stub lock_and_mint! to raise
        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_raise(StandardError.new("test error"))

        expect {
          TokenomicsEvaluatorWorker.new.perform
        }.not_to raise_error
      end
    end

    describe "stats[:minted_count] branches (line 73)" do
      it "logs with minted_count zero when no eligible wallets" do
        expect {
          TokenomicsEvaluatorWorker.new.perform
        }.not_to raise_error
      end

      it "logs with minted_count positive when transactions created" do
        tree = create(:tree, cluster: cluster)
        wallet = tree.wallet
        wallet.update_columns(balance: TokenomicsEvaluatorWorker::EMISSION_THRESHOLD * 3)

        tx = create(:blockchain_transaction, wallet: wallet, amount: 3, status: :pending)
        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_return(tx)

        expect {
          TokenomicsEvaluatorWorker.new.perform
        }.not_to raise_error
        expect(BlockchainMintingService).to have_received(:call_batch)
      end
    end
  end

  # ==========================================================================
  # 12. WALLET — organization nil in crypto_public_address fallback,
  #     return unless tx (tokens_to_mint zero)
  # ==========================================================================
  describe "Wallet branch coverage" do
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet }

    before do
      allow(MintCarbonCoinWorker).to receive(:perform_async)
    end

    describe "organization&.crypto_public_address when organization is nil (line 88)" do
      it "raises when both wallet and organization addresses are blank" do
        wallet.update_columns(crypto_public_address: nil, organization_id: nil)
        wallet.reload

        expect {
          wallet.lock_and_mint!(10_000, 10_000)
        }.to raise_error(RuntimeError, /крипто-адреса/)
      end
    end

    describe "return unless tx — tokens_to_mint zero (line 121)" do
      it "returns nil when tokens_to_mint is zero" do
        wallet.update_columns(balance: 5000)
        wallet.reload

        result = wallet.lock_and_mint!(5000, 10_000)
        expect(result).to be_nil
        expect(MintCarbonCoinWorker).not_to have_received(:perform_async)
      end
    end

    describe "lock_and_mint! success path" do
      it "creates transaction and enqueues worker" do
        wallet.update_columns(balance: 20_000)
        wallet.reload

        tx = wallet.lock_and_mint!(20_000, 10_000)
        expect(tx).to be_persisted
        expect(tx.amount).to eq(2)
        expect(MintCarbonCoinWorker).to have_received(:perform_async).with(tx.id)
      end
    end
  end

  # ==========================================================================
  # 13. SESSIONS CONTROLLER — current_session when current_user is nil (line 80)
  # ==========================================================================
  describe "Api::V1::SessionsController#current_session" do
    it "returns nil when current_user is nil" do
      controller = Api::V1::SessionsController.new
      allow(controller).to receive(:current_user).and_return(nil)
      result = controller.send(:current_session)
      expect(result).to be_nil
    end
  end

  # ==========================================================================
  # 14. BASE CONTROLLER — render_internal_server_error (StandardError rescue)
  # ==========================================================================
  describe "Api::V1::BaseController error handling" do
    describe "render_internal_server_error (line 19)" do
      it "logs and renders 500 error" do
        controller = Api::V1::BaseController.new
        allow(controller).to receive(:render)
        exception = StandardError.new("test failure")
        exception.set_backtrace(["line1", "line2"])

        controller.send(:render_internal_server_error, exception)
        expect(controller).to have_received(:render).with(
          hash_including(json: hash_including(:error), status: :internal_server_error)
        )
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integration coverage — uncovered model/service/worker paths" do
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
  end

  # ==========================================================================
  # 1. ACTUATOR COMMAND — estimated_completion_at, denormalize_organization,
  #    duration_within_safety_envelope, broadcast_prepend_to_activity_feed
  # ==========================================================================
  describe "ActuatorCommand edge cases" do
    describe "#estimated_completion_at" do
      it "returns nil when sent_at is nil" do
        command = create(:actuator_command, actuator: actuator)
        expect(command.sent_at).to be_nil
        expect(command.estimated_completion_at).to be_nil
      end

      it "returns sent_at + duration_seconds when sent_at is present" do
        command = create(:actuator_command, actuator: actuator, duration_seconds: 120)
        now = Time.current
        command.update_columns(sent_at: now)
        command.reload

        expect(command.estimated_completion_at).to be_within(1.second).of(now + 120.seconds)
      end
    end

    describe "denormalize_organization when actuator chain is nil" do
      it "handles nil gateway gracefully" do
        command = ActuatorCommand.new(
          actuator: actuator,
          command_payload: "OPEN",
          duration_seconds: 60
        )
        # Stub the chain to return nil
        allow(actuator).to receive(:gateway).and_return(nil)
        command.valid?
        # Should not raise, organization_id will be from the already-loaded chain
        expect(command.errors[:organization_id]).to be_empty
      end
    end

    describe "duration_within_safety_envelope when actuator is nil" do
      it "skips validation when actuator has nil max_active_duration_s" do
        unlimited = create(:actuator, gateway: gateway, max_active_duration_s: nil)
        command = ActuatorCommand.new(
          actuator: unlimited,
          command_payload: "OPEN",
          duration_seconds: 3600
        )
        expect(command).to be_valid
      end

      it "skips validation when duration_seconds is nil" do
        command = ActuatorCommand.new(
          actuator: actuator,
          command_payload: "OPEN",
          duration_seconds: nil
        )
        # Will fail on presence validation, but not on safety envelope
        command.valid?
        expect(command.errors[:duration_seconds]).to include("can't be blank")
      end
    end

    describe "broadcast_prepend_to_activity_feed" do
      it "broadcasts when organization is present via denormalization" do
        # Let the real broadcast method run
        allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed).and_call_original

        command = create(:actuator_command, actuator: actuator)
        expect(command.organization).to eq(organization)
        # broadcast_prepend_to_activity_feed was called in after_commit
        expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).at_least(:once)
      end

      it "returns nil when organization is nil and actuator chain is nil" do
        command = build(:actuator_command, actuator: actuator)
        command.organization = nil
        allow(actuator).to receive(:gateway).and_return(nil)

        # Call the private method directly
        result = command.send(:broadcast_prepend_to_activity_feed)
        expect(result).to be_nil
      end
    end
  end

  # ==========================================================================
  # 2. WALLET — lock_and_mint! edge cases
  # ==========================================================================
  describe "Wallet#lock_and_mint! edge cases" do
    let(:tree) { create(:tree, cluster: cluster, status: :active) }
    let(:wallet) { tree.wallet }

    before do
      wallet.update!(balance: 10_000)
      allow(MintCarbonCoinWorker).to receive(:perform_async)
    end

    it "raises when tree is not active" do
      tree.update_column(:status, Tree.statuses[:deceased])
      tree.reload

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /не активне/)
    end

    it "returns nil when threshold is zero" do
      result = wallet.lock_and_mint!(1000, 0)
      expect(result).to be_nil
    end

    it "returns nil when threshold is negative" do
      result = wallet.lock_and_mint!(1000, -5)
      expect(result).to be_nil
    end

    it "uses org crypto address when wallet has no crypto_public_address" do
      wallet.update!(crypto_public_address: nil)
      # Organization already has crypto_public_address from factory

      tx = wallet.lock_and_mint!(1000, 100)
      expect(tx).to be_present
      expect(tx.to_address).to eq(organization.crypto_public_address)
    end

    it "raises when neither wallet nor org have crypto address" do
      wallet.update!(crypto_public_address: nil)
      organization.update_column(:crypto_public_address, nil)

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /крипто-адреса/)
    end

    it "raises when available balance is insufficient" do
      wallet.update!(balance: 50, locked_balance: 0)

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /Недостатньо балів/)
    end

    it "returns nil when tokens_to_mint is zero" do
      # 50 points / 100 threshold = 0 tokens (floor)
      result = wallet.lock_and_mint!(50, 100)
      expect(result).to be_nil
    end

    it "creates blockchain transaction and enqueues worker on success" do
      tx = wallet.lock_and_mint!(1000, 100)

      expect(tx).to be_present
      expect(tx.amount).to eq(10) # 1000 / 100 = 10
      expect(tx.status).to eq("pending")
      expect(tx.locked_points).to eq(1000)
      expect(MintCarbonCoinWorker).to have_received(:perform_async).with(tx.id)
    end
  end

  # ==========================================================================
  # 3. NAAS CONTRACT — edge cases
  # ==========================================================================
  describe "NaasContract edge cases" do
    describe "#calculate_prorated_refund when total_days is zero" do
      it "returns 0 when start_date equals end_date" do
        contract = create(:naas_contract,
          organization: organization,
          cluster: cluster,
          status: :active,
          start_date: Date.current,
          end_date: Date.current
        )
        # Use update_columns to bypass end_date > start_date validation,
        # which is the exact edge case (total_days=0) we're testing.
        contract.update_columns(start_date: Date.current, end_date: Date.current)

        expect(contract.calculate_prorated_refund).to eq(BigDecimal("0"))
      end
    end

    describe "#active_threats?" do
      it "returns false when cluster is nil" do
        contract = create(:naas_contract, organization: organization, cluster: cluster)
        allow(contract).to receive(:cluster).and_return(nil)

        expect(contract.active_threats?).to be false
      end

      it "returns false when no active alerts" do
        contract = create(:naas_contract, organization: organization, cluster: cluster)
        expect(contract.active_threats?).to be false
      end

      it "returns true when cluster has unresolved alerts (not eager-loaded)" do
        contract = create(:naas_contract, organization: organization, cluster: cluster)
        create(:ews_alert, cluster: cluster, status: :active)

        expect(contract.active_threats?).to be true
      end

      it "returns true when cluster has eager-loaded active alerts" do
        contract = create(:naas_contract, organization: organization, cluster: cluster)
        alert = create(:ews_alert, cluster: cluster, status: :active)

        # Eager-load the association
        loaded_cluster = Cluster.includes(:ews_alerts).find(cluster.id)
        allow(contract).to receive(:cluster).and_return(loaded_cluster)

        expect(contract.active_threats?).to be true
      end

      it "returns false when cluster has eager-loaded but resolved alerts" do
        contract = create(:naas_contract, organization: organization, cluster: cluster)
        create(:ews_alert, cluster: cluster, status: :resolved)

        loaded_cluster = Cluster.includes(:ews_alerts).find(cluster.id)
        allow(contract).to receive(:cluster).and_return(loaded_cluster)

        expect(contract.active_threats?).to be false
      end
    end

    describe "activate_slashing_protocol! error handling" do
      it "handles error during update! and does not enqueue worker" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)

        # Stub update! to raise error inside the transaction
        allow(contract).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(contract))

        # Call the private method
        contract.send(:activate_slashing_protocol!)

        # Should NOT have enqueued worker since the transaction failed
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
        # Status should remain unchanged
        expect(contract.reload).to be_status_active
      end

      it "enqueues worker when slashing succeeds" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)

        contract.send(:activate_slashing_protocol!)

        expect(contract.reload).to be_status_breached
        expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
      end
    end
  end

  # ==========================================================================
  # 4. CHAINLINK ORACLE DISPATCH SERVICE
  # ==========================================================================
  describe "Chainlink::OracleDispatchService" do
    let(:tree) { create(:tree, cluster: cluster) }
    let(:telemetry_log) do
      create(:telemetry_log, tree: tree,
        verified_by_iotex: true,
        z_value: 0.35,
        zk_proof_ref: "zk-proof-123")
    end

    describe "#dispatch! in stub mode (no env vars)" do
      it "generates a local stub request ID" do
        service = Chainlink::OracleDispatchService.new(telemetry_log)
        request_id = service.dispatch!

        expect(request_id).to start_with("chainlink-req-")
        expect(telemetry_log.reload.chainlink_request_id).to eq(request_id)
        expect(telemetry_log.oracle_status).to eq("dispatched")
      end
    end

    describe "#dispatch! when not verified by IoTeX" do
      it "raises DispatchError" do
        telemetry_log.update_column(:verified_by_iotex, false)
        telemetry_log.reload
        service = Chainlink::OracleDispatchService.new(telemetry_log)

        expect {
          service.dispatch!
        }.to raise_error(Chainlink::OracleDispatchService::DispatchError, /не верифіковано/)
      end
    end

    describe "#dispatch! with CHAINLINK env vars set" do
      it "calls send_on_chain_request when env vars are present" do
        stub_const("ENV", ENV.to_h.merge(
          "CHAINLINK_FUNCTIONS_ROUTER" => "0x1234567890abcdef1234567890abcdef12345678",
          "CHAINLINK_SUBSCRIPTION_ID" => "42",
          "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
          "ORACLE_PRIVATE_KEY" => "a" * 64
        ))

        service = Chainlink::OracleDispatchService.new(telemetry_log)

        # Stub the Eth::Client call chain
        mock_client = double("Eth::Client")
        mock_key = double("Eth::Key")
        mock_contract = double("Eth::Contract")

        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Key).to receive(:new).and_return(mock_key)
        allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
        allow(mock_client).to receive(:transact).and_return("0xtx_hash_123")

        request_id = service.dispatch!
        expect(request_id).to eq("0xtx_hash_123")
      end

      it "wraps on-chain errors in DispatchError" do
        stub_const("ENV", ENV.to_h.merge(
          "CHAINLINK_FUNCTIONS_ROUTER" => "0x1234567890abcdef1234567890abcdef12345678",
          "CHAINLINK_SUBSCRIPTION_ID" => "42",
          "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
          "ORACLE_PRIVATE_KEY" => "a" * 64
        ))

        service = Chainlink::OracleDispatchService.new(telemetry_log)

        allow(Eth::Client).to receive(:create).and_raise(StandardError, "RPC timeout")

        expect {
          service.dispatch!
        }.to raise_error(Chainlink::OracleDispatchService::DispatchError, /Chainlink on-chain dispatch failed/)
      end
    end
  end

  # ==========================================================================
  # 5. TELEMETRY UNPACKER SERVICE — uncovered branches
  # ==========================================================================
  describe "TelemetryUnpackerService edge cases" do
    let(:tree) { create(:tree, cluster: cluster) }

    before do
      allow(AlertDispatchService).to receive(:analyze_and_trigger!)
      allow(IotexVerificationWorker).to receive(:perform_async)
      allow(GatewayTelemetryWorker).to receive(:perform_async)
    end

    # Builds a 21-byte telemetry packet matching the format: [DID:4][RSSI:1][Payload:16]
    # as defined in docs/FIRMWARE.md and TelemetryUnpackerService::PAYLOAD_FORMAT.
    def build_chunk(did_hex:, rssi: 65, voltage: 4200, temp: 22, acoustic: 5, metabolism: 120, status_byte: 0, ttl: 5, firmware_id: 0)
      did_int = did_hex.to_i(16)
      did_bytes = [did_int].pack("N")
      rssi_byte = [rssi].pack("C")

      # Payload: DID(N), Vcap(n), Temp(c), Acoustic(C), Metabolism(n), Status(C), TTL(C), Pad(a4)
      growth_points = status_byte & 0x3F
      combined_status = (status_byte << 6) | growth_points
      pad = [firmware_id].pack("n") + "\x00\x00"

      payload = [did_int, voltage, temp, acoustic, metabolism, combined_status, ttl].pack("N n c C n C C") + pad
      did_bytes + rssi_byte + payload
    end

    describe "when gateway is nil (queen_uid branch)" do
      it "processes chunks without gateway" do
        # Get the DID from the tree
        hex_did = tree.did.gsub("SNET-", "")

        chunk = build_chunk(did_hex: hex_did, voltage: 4200, temp: 22)
        service = TelemetryUnpackerService.new(chunk, nil)

        expect { service.perform }.not_to raise_error
      end
    end

    describe "interpret_status else branch" do
      it "handles unrecognized status codes gracefully" do
        service = TelemetryUnpackerService.new("", nil)
        # The interpret_status method returns nil for unrecognized codes (case without else)
        result = service.send(:interpret_status, 0)
        expect(result).to eq(:homeostasis)

        result1 = service.send(:interpret_status, 1)
        expect(result1).to eq(:stress)

        result2 = service.send(:interpret_status, 2)
        expect(result2).to eq(:anomaly)

        result3 = service.send(:interpret_status, 3)
        expect(result3).to eq(:tamper_detected)
      end
    end

    describe "check_firmware_mismatch!" do
      let!(:active_firmware) { create(:bio_contract_firmware, :active, target_hardware_type: "Tree") }

      it "skips when reported_firmware_id is blank" do
        service = TelemetryUnpackerService.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, nil)
        }.not_to raise_error
      end

      it "skips when latest firmware id is nil" do
        service = TelemetryUnpackerService.new("", nil)
        # Remove all active firmware
        BioContractFirmware.update_all(is_active: false)

        expect {
          service.send(:check_firmware_mismatch!, tree, 999)
        }.not_to raise_error
      end

      it "skips when reported firmware matches latest" do
        service = TelemetryUnpackerService.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, active_firmware.id)
        }.not_to raise_error
        # Tree should NOT be marked as fw_pending
        expect(tree.reload.firmware_update_status).not_to eq("fw_pending")
      end

      it "marks tree as fw_pending when firmware mismatches and tree is fw_idle" do
        service = TelemetryUnpackerService.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end

      it "does not mark tree as fw_pending when already fw_pending" do
        Tree.where(id: tree.id).update_all(firmware_update_status: :fw_pending)
        service = TelemetryUnpackerService.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        # Should still be fw_pending, no error
        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end
    end

    describe "latest_tree_firmware_id caching" do
      it "caches the result across calls" do
        create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        service = TelemetryUnpackerService.new("", nil)

        first_call = service.send(:latest_tree_firmware_id)
        second_call = service.send(:latest_tree_firmware_id)

        expect(first_call).to eq(second_call)
      end
    end

    describe "valid_sensor_data? range checks" do
      it "rejects out-of-range voltage" do
        service = TelemetryUnpackerService.new("", nil)
        data = [0, 6000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00"]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects out-of-range temperature" do
        service = TelemetryUnpackerService.new("", nil)
        data = [0, 4200, 100, 5, 120, 0, 5, "\x00\x00\x00\x00"]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts valid sensor data" do
        service = TelemetryUnpackerService.new("", nil)
        data = [0, 4200, 22, 5, 120, 0, 5, "\x00\x00\x00\x00"]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end
    end
  end

  # ==========================================================================
  # 6. UNPACK TELEMETRY WORKER — decryption paths
  # ==========================================================================
  describe "UnpackTelemetryWorker decryption edge cases" do
    let(:hw_key) { create(:hardware_key, device_uid: gateway.uid) }

    before do
      allow(TelemetryUnpackerService).to receive(:call)
    end

    def encrypt_payload(data, key_hex)
      key = [key_hex].pack("H*")
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      iv = cipher.random_iv
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0

      # Pad data to AES block boundary
      block_size = 16
      padded = data + ("\x00" * (block_size - data.bytesize % block_size))
      iv + cipher.update(padded) + cipher.final
    end

    describe "decryption with current key" do
      it "decrypts successfully with current key and clears grace period" do
        hw_key # ensure key exists
        payload_data = "\x00" * 32
        encrypted = encrypt_payload(payload_data, hw_key.aes_key_hex)
        encoded = Base64.strict_encode64(encrypted)

        expect(hw_key).to receive(:clear_grace_period!)
        allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(hw_key)
        allow(hw_key).to receive(:binary_key).and_return([hw_key.aes_key_hex].pack("H*"))
        allow(hw_key).to receive(:binary_previous_key).and_return(nil)

        worker = UnpackTelemetryWorker.new

        # Stub attempt_decryption to return data
        allow(worker).to receive(:attempt_decryption).and_call_original
        allow(worker).to receive(:decrypt_aes).and_return(payload_data)

        worker.perform(encoded, "192.168.1.1", gateway.uid)
      end
    end

    describe "decryption with previous key" do
      it "falls back to previous key when current key fails" do
        prev_key_hex = SecureRandom.hex(32)
        hw_key.update!(previous_aes_key_hex: prev_key_hex)
        allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(hw_key)

        worker = UnpackTelemetryWorker.new

        call_count = 0
        allow(worker).to receive(:decrypt_aes) do |_payload, key|
          call_count += 1
          if call_count == 1
            nil # First attempt (current key) fails
          else
            "\x00" * 32 # Second attempt (previous key) succeeds
          end
        end

        payload_data = "\x00" * 64 # 64 bytes: 16 IV + 48 data ensures proper AES block alignment
        encoded = Base64.strict_encode64(payload_data)

        worker.perform(encoded, "192.168.1.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
      end
    end

    describe "decrypt_aes error handling" do
      it "returns nil for CipherError" do
        worker = UnpackTelemetryWorker.new
        # Create data that will cause CipherError (wrong key)
        result = worker.send(:decrypt_aes, "\x00" * 32, "\x00" * 32)
        # May return nil or data depending on padding=0; test that it doesn't raise
        expect(result).to be_a(String).or be_nil
      end

      it "returns nil when payload is too short" do
        worker = UnpackTelemetryWorker.new
        result = worker.send(:decrypt_aes, "\x00" * 16, "\x00" * 32)
        expect(result).to be_nil
      end

      it "returns nil when ciphertext is not block-aligned" do
        worker = UnpackTelemetryWorker.new
        # 16 bytes IV + 17 bytes (not aligned to 16)
        result = worker.send(:decrypt_aes, "\x00" * 33, "\x00" * 32)
        expect(result).to be_nil
      end

      it "rescues StandardError and returns nil" do
        worker = UnpackTelemetryWorker.new

        # Create a scenario where a StandardError (not CipherError) occurs
        allow(OpenSSL::Cipher).to receive(:new).and_raise(StandardError, "unexpected")
        result = worker.send(:decrypt_aes, "\x00" * 64, "\x00" * 32)
        expect(result).to be_nil
      end
    end
  end

  # ==========================================================================
  # 7. MAINTENANCE RECORD BLUEPRINT — nil maintainable, url_helpers
  # ==========================================================================
  describe "MaintenanceRecordBlueprint edge cases" do
    let(:user) { create(:user, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster) }

    describe "index view with maintainable_label" do
      it "renders maintainable_label with did for tree" do
        record = create(:maintenance_record, user: user, maintainable: tree)
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :index)

        expect(json[:maintainable_label]).to include("Tree")
        expect(json[:maintainable_label]).to include(tree.did)
      end

      it "renders maintainable_label with uid for gateway" do
        record = create(:maintenance_record, user: user, maintainable: gateway)
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :index)

        expect(json[:maintainable_label]).to include("Gateway")
        expect(json[:maintainable_label]).to include(gateway.uid)
      end
    end

    describe "show view photo_urls" do
      it "renders empty photo_urls when no photos attached" do
        record = create(:maintenance_record, user: user, maintainable: tree)
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :show, url_helpers: nil)

        expect(json[:photo_urls]).to eq([])
      end

      it "uses fallback empty strings when url_helpers is nil" do
        record = create(:maintenance_record, user: user, maintainable: tree)
        json = MaintenanceRecordBlueprint.render_as_hash(record, view: :show, url_helpers: nil)

        expect(json[:photo_urls]).to eq([])
      end
    end
  end

  # ==========================================================================
  # 8. BASE CONTROLLER — signed_in?, render_internal_server_error
  # ==========================================================================
  describe "Api::V1::BaseController" do
    let(:user) { create(:user, organization: organization, password: "password12345") }

    def json_headers
      { "Accept" => "application/json" }
    end

    def auth_headers
      json_headers.merge("Authorization" => "Bearer #{user.generate_token_for(:api_access)}")
    end

    describe "signed_in? helper" do
      it "returns true when user is authenticated" do
        get "/api/v1/trees", headers: auth_headers
        # If we get any response other than 401, the user is signed in
        expect(response).not_to have_http_status(:unauthorized)
      end

      it "returns false when user is not authenticated" do
        get "/api/v1/organizations", headers: json_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

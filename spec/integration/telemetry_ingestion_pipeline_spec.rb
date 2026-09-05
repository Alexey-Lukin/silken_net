# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telemetry ingestion pipeline end-to-end" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "TelemetryUnpackerService processes binary batch" do
    let(:did_hex) { "0000ABCD" }
    let(:extracted_did) { format("SNET-%08X", did_hex.to_i(16)) }
    let!(:tree) do
      create(:tree, did: extracted_did, cluster: cluster, tree_family: tree_family)
    end

    before do
      tree.create_device_calibration! if tree.device_calibration.nil?
      # [SEC.11] HardwareKey with K_seed is required by
      # TelemetryUnpackerService — every tree gets one at provisioning.
      tree.create_hardware_key!(
        device_uid: tree.did,
        # Post-ARCH.42: Tree LoRa AES-128 key = 16 bytes / 32 hex chars.
        # Gateway-shape (64 hex) залишається для Queen HardwareKey rows.
        aes_key_hex: SecureRandom.hex(16).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )
      allow(AlertDispatchService).to receive(:analyze_and_trigger!)
      # [SEC.11] Sole entry-point is calculate_z_from_state — pin to a
      # deterministic Z so the integration assertions are stable.
      allow(SilkenNet::Attractor).to receive(:calculate_z_from_state)
        .and_return([ 25.0, 0.1, 0.2, 0.3 ])
    end

    # build_chunk lives in spec/support/telemetry_chunk_helper.rb —
    # auto-included by file_path match. The positional signature is
    # identical (8 args + optional `pad`).

    it "creates telemetry log, updates voltage, and credits wallet" do
      # status_byte: lower 6 bits = growth_points (10), upper 2 bits = bio_status (0 = homeostasis)
      chunk = build_chunk(did_hex, -70, 3800, 22, 5, 120, 10, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.to change(TelemetryLog, :count).by(1)

      log = TelemetryLog.last
      expect(log.tree).to eq(tree)
      expect(log.rssi).to eq(-70)
      expect(log.bio_status).to eq("homeostasis")
      expect(log.z_value).to be_present

      tree.reload
      expect(tree.last_seen_at).to be_present
      expect(tree.wallet.balance).to be > 0
    end

    it "rejects out-of-range sensor data (voltage > 5000 mV)" do
      chunk = build_chunk(did_hex, -70, 6000, 22, 5, 120, 0, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.not_to change(TelemetryLog, :count)
    end

    it "skips unknown DID gracefully" do
      chunk = build_chunk("FFFFFFFF", -70, 3800, 22, 5, 120, 0, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.not_to change(TelemetryLog, :count)
    end
  end

  describe "telemetry triggers alert dispatch" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates a fire alert when temperature exceeds threshold" do
      log = create(:telemetry_log, tree: tree, temperature_c: 70,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 25.0)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("fire_detected")
      expect(alert.severity).to eq("critical")
      expect(alert.tree).to eq(tree)
      expect(alert.cluster).to eq(cluster)
    end

    # ⛔ [E.64 ⚖️ 2026-09-05] Наскрізне дзеркало юніт-піна: НИЗЬКИЙ Z сам собою
    # алерту БІЛЬШЕ НЕ дає — серверну Z-гілку знято як Z-похідний вердикт про
    # здоровʼя (роль Z = DCI-only, `05_05 §8.1`), тож судить лише ПРИСТРІЙНИЙ
    # `bio_status`. Приклад свідомо лишає `z_value: 0.1` — значення, що доти
    # гарантовано підіймало алерт, — інакше пін не відрізнити від «взяли інші дані».
    it "НЕ створює алерт на низькому z_value, якщо пристрій каже homeostasis" do
      log = create(:telemetry_log, tree: tree, temperature_c: 20,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 0.1)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .not_to change(EwsAlert, :count)
    end

    it "створює drought-алерт, коли ПРИСТРІЙ повідомив stress" do
      log = create(:telemetry_log, tree: tree, temperature_c: 20,
                                   bio_status: :stress, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 0.1)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("severe_drought")
      expect(EwsAlert.last.message_key).to eq("hydrological_stress")
    end

    it "respects silence filter — does not duplicate alerts within window" do
      log1 = create(:telemetry_log, tree: tree, temperature_c: 70,
                                    bio_status: :homeostasis, voltage_mv: 3500,
                                    acoustic_events: 5, z_value: 25.0)
      AlertDispatchService.analyze_and_trigger!(log1)
      expect(EwsAlert.count).to eq(1)

      log2 = create(:telemetry_log, tree: tree, temperature_c: 75,
                                    bio_status: :homeostasis, voltage_mv: 3500,
                                    acoustic_events: 5, z_value: 25.0)
      # Silence filter should prevent duplicate fire alert
      expect { AlertDispatchService.analyze_and_trigger!(log2) }
        .not_to change(EwsAlert, :count)
    end
  end
end

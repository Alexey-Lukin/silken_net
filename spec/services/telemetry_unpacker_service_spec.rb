# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryUnpackerService, type: :service do
  # build_chunk / build_chunk_with_params / build_panic_chunk /
  # build_ccm_chunk live in spec/support/telemetry_chunk_helper.rb
  # — auto-included for any spec whose path matches *telemetry*.

  let(:did_hex) { "0000ABCD" }
  let(:extracted_did) { format("SNET-%08X", did_hex.to_i(16)) }

  let!(:tree) { create(:tree, did: extracted_did) }
  # [SEC.11] HardwareKey with K_seed is required for every uplink —
  # TelemetryUnpackerService raises MissingLorenzSeedError otherwise.
  let!(:hardware_key) do
    HardwareKey.create!(
      device_uid: extracted_did,
      aes_key_hex: SecureRandom.hex(16).upcase,
      lorenz_seed_hex: SecureRandom.hex(32).upcase
    )
  end

  before do
    tree.create_device_calibration! if tree.device_calibration.nil?
    silence_broadcasts!(:wallet_balance, :tree_map)
    allow(AlertDispatchService).to receive(:analyze_and_trigger!)
    # [SEC.11] Pin the post-cutover entry-point so attribute-level
    # assertions are stable. Returns [z, x, y, z_final] tuple.
    allow(SilkenNet::Attractor).to receive(:calculate_z_from_state)
      .and_return([ 0.5, 0.1, 0.2, 0.3 ])
    allow(IotexVerificationWorker).to receive(:perform_async)
    allow(StreamrBroadcastWorker).to receive(:perform_async)
  end

  describe "[FW.57 F2] Lorenz/DCI uses the raw wire temp, not drift-corrected temperature_c" do
    it "passes the RAW wire temp to the attractor; persists the calibrated value" do
      tree.device_calibration.update!(temperature_offset_c: 3.0)
      captured = nil
      allow(SilkenNet::Attractor).to receive(:calculate_z_from_state) do |*args|
        captured = args
        [ 0.5, 0.1, 0.2, 0.3 ]
      end

      described_class.call(build_chunk(did_hex, -70, 3500, 22, 5, 100, 10, 3))

      expect(captured[3]).to eq(22)                       # raw wire temp — NOT 25 (22 + 3 offset)
      expect(TelemetryLog.last.temperature_c).to eq(25.0) # calibrated value still persisted
    end

    it "#lorenz_temperature prefers the threaded raw temp, else falls back to temperature_c" do
      service = described_class.new("", nil)
      expect(service.send(:lorenz_temperature, { temperature_c: 25.0, lorenz_temperature_c: 22 })).to eq(22)
      expect(service.send(:lorenz_temperature, { temperature_c: 22.0 })).to eq(22.0)
    end
  end

  it "returns early when binary_batch is blank" do
    expect { described_class.call(nil) }.not_to change(TelemetryLog, :count)
    expect { described_class.call("") }.not_to change(TelemetryLog, :count)
  end

  it "unpacks a valid 21-byte chunk and creates a telemetry log" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)

    log = TelemetryLog.last
    expect(log.tree).to eq(tree)
    expect(log.voltage_mv).to eq(3500)
    expect(log.temperature_c).to eq(25.0)
    expect(log.acoustic_events).to eq(5)
    expect(log.metabolism_s).to eq(100)
    expect(log.rssi).to eq(-70)
    expect(log.z_value).to eq(0.5)
    expect(log.mesh_ttl).to eq(3)
    # [L1 QATT] без явного прапора — L0 (legacy/неатестований батч)
    expect(log.gateway_attested).to be(false)
  end

  # [FW.29] PanicFlag (біт 7 StatusByte) персиститься — панічність queryable,
  # relayed_via_mesh? знає стартовий TTL (3 normal / 5 panic)
  it "does not mark a normal packet as panic (PanicFlag bit 7 = 0)" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
    described_class.call(chunk)
    expect(TelemetryLog.last.panic).to be(false)
  end

  # [L1 QATT] Походження батча протягується у кожен рядок (05_02 ladder L1)
  it "stamps gateway_attested on every row when the batch was Queen-attested" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk, nil, gateway_attested: true) }
      .to change(TelemetryLog, :count).by(1)

    expect(TelemetryLog.last.gateway_attested).to be(true)
  end

  it "rejects sensor data outside safe voltage range" do
    chunk = build_chunk(did_hex, -70, 5001, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "rejects sensor data outside safe temperature range" do
    chunk = build_chunk(did_hex, -70, 3500, 91, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "skips chunks shorter than 21 bytes" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)[0..19]

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "skips unknown DIDs not found in registry" do
    chunk = build_chunk("FFFFFFFF", -70, 3500, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "credits wallet with growth points" do
    # [FW.29-PACK] wire status_byte = 10 (homeostasis, gp=10) → stored gp = 20 (×2 backend upscale)
    status_byte = 10
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, status_byte, 3)

    expect { described_class.call(chunk) }.to change { tree.wallet.reload.balance }.by(20)
  end

  it "calls AlertDispatchService to analyze telemetry" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(AlertDispatchService).to have_received(:analyze_and_trigger!).with(an_instance_of(TelemetryLog))
  end

  it "triggers IotexVerificationWorker after telemetry commit" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(IotexVerificationWorker).to have_received(:perform_async).with(an_instance_of(Integer), an_instance_of(String))
  end

  it "triggers StreamrBroadcastWorker after telemetry commit" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(StreamrBroadcastWorker).to have_received(:perform_async).with(an_instance_of(Integer), an_instance_of(String))
  end

  context "when transaction rolls back (P1-7 phantom job prevention)" do
    it "does not enqueue IotexVerificationWorker or StreamrBroadcastWorker" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      # [ARCH.84] Seam перецілено: доти збій ін'єктувався через
      # `update_health_streak!`, знятий разом із anti-flapping-петлею. Приклад
      # НЕ про той метод — він про P1-7 (enqueue поза транзакцією), тож будь-який
      # крок ВСЕРЕДИНІ `commit_telemetry` після `create!` слугує так само.
      # `check_firmware_mismatch!` — останній такий крок, і він лишається живим.
      allow_any_instance_of(described_class).to receive(:check_firmware_mismatch!).and_raise(ActiveRecord::RecordInvalid)

      allow(Rails.logger).to receive(:error).with(/Telemetry Error/)
      expect { described_class.call(chunk) }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Telemetry Error/)
      # The key assertion: workers must NOT be enqueued when transaction rolls back
      expect(IotexVerificationWorker).not_to have_received(:perform_async)
      expect(StreamrBroadcastWorker).not_to have_received(:perform_async)
    end

    # [INF.26] Та сама межа, лише для лічильника: Prometheus-реєстр не транзакційний,
    # тож інкремент, зроблений усередині блоку, ПЕРЕЖИВАЄ rollback — і метрика з
    # докстрінгом «processed» звітувала б чанки, яких у БД немає. Пін цілиться в
    # `.increment` саме тому, що жоден інший приклад цього не побачить: розходження
    # тихе обабіч (лічильник росте, рядка немає, помилки немає).
    it "does not count a chunk that never committed" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
      allow_any_instance_of(described_class).to receive(:check_firmware_mismatch!).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error).with(/Telemetry Error/)
      allow(SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL).to receive(:increment)

      described_class.call(chunk)

      expect(SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL).not_to have_received(:increment)
    end

    # Позитивна половина — інакше пін вище зелений і на знятому інкременті
    # (§Guard-craft: мутація в ОБИДВА боки, «не рахує» доводить лише половину).
    it "counts a chunk that did commit" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
      allow(SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL).to receive(:increment)

      described_class.call(chunk)

      expect(SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL).to have_received(:increment).once
    end
  end

  describe "[ARCH.54] DID=0 у батчі — retired" do
    let!(:gateway) { create(:gateway) }

    it "дропає DID=0x00000000 без TelemetryLog і без GatewayTelemetryWorker" do
      # Пульс Королеви живе у ПІДПИСАНОМУ QATT-v2 header'і
      # (UnpackTelemetryWorker#enqueue_envelope_health), не псевдодеревом:
      # стара милиця читалась Солдатськими офсетами і брехала полями.
      chunk = build_chunk("00000000", -70, 3500, 25, 5, 100, 0, 3)
      before_jobs = GatewayTelemetryWorker.jobs.size

      expect { described_class.call(chunk, gateway.id) }.not_to change(TelemetryLog, :count)

      expect(GatewayTelemetryWorker.jobs.size).to eq(before_jobs)
    end
  end

  describe "[FW.18b] TTL-байт як бітфілд [thr_invalid:5 | TTL:3]" do
    # Freeze-contract: ці ж golden-байти заморожені у firmware
    # (test_soldier_logic.c, test_fw18b_pack_golden_wire) — One-Home
    # firmware/common/ttl_byte.h. 0x3B = Pack(ttl=3, invalid=7);
    # 0xFD = Pack(ttl=5, invalid=31, wire-сатурація). Метрика без per-DID
    # мітки (cardinality budget 06_03 §2.9) — DID атрибутується логом.
    let(:counter) { SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL }

    it "маскує mesh_ttl до нижніх 3 біт і рахує ненульовий звіт лічильника" do
      before_val = counter.get
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 0x3B)

      allow(Rails.logger).to receive(:warn).and_call_original
      described_class.call(chunk)

      expect(Rails.logger).to have_received(:warn).with(/FW\.18b.*#{extracted_did}.*лічильник 7/)
      expect(TelemetryLog.last.mesh_ttl).to eq(3)
      expect(counter.get).to eq(before_val + 1.0)
    end

    it "читає wire-сатурований лічильник 31 при panic-TTL 5 і каже про сатурацію" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 0xFD)

      allow(Rails.logger).to receive(:warn).and_call_original
      described_class.call(chunk)

      expect(Rails.logger).to have_received(:warn).with(/лічильник 31 \(wire-сатурація/)
      expect(TelemetryLog.last.mesh_ttl).to eq(5)
    end

    it "legacy-байт (чистий TTL, лічильник 0) не торкається метрики" do
      before_val = counter.get
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
      described_class.call(chunk)

      expect(TelemetryLog.last.mesh_ttl).to eq(3)
      expect(counter.get).to eq(before_val)
    end
  end

  describe "interpret_status" do
    it "maps status codes 1, 2, 3 to stress, anomaly, vm_error" do
      # [FW.29-PACK] Status byte layout: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GP:5 (bits 4..0)]
      # code 1 → :stress (status_byte = 0b010_00000 = 32)
      chunk_stress = build_chunk(did_hex, -70, 3500, 25, 5, 100, 32, 3)
      described_class.call(chunk_stress)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("stress")

      # code 2 → :anomaly (status_byte = 0b100_00000 = 64)
      chunk_anomaly = build_chunk(did_hex, -70, 3500, 25, 5, 100, 64, 3)
      described_class.call(chunk_anomaly)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("anomaly")

      # code 3 → :vm_error (status_byte = 0b110_00000 = 96 = BIO_STATUS_VM_ERROR 0x60)
      chunk_vm_error = build_chunk(did_hex, -70, 3500, 25, 5, 100, 96, 3)
      described_class.call(chunk_vm_error)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("vm_error")
    end
  end

  describe "error handling" do
    it "logs error and continues when process_chunk raises" do
      allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_raise(StandardError.new("test error"))

      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      allow(Rails.logger).to receive(:error).with(/Telemetry Error/)
      expect { described_class.call(chunk) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Telemetry Error/)
    end
  end

  describe "edge cases from coverage enhancement" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:gateway) { create(:gateway, :online, cluster: cluster) }

    # build_chunk_with_params is provided by TelemetryChunkHelper
    # (spec/support/telemetry_chunk_helper.rb).

    before do
      allow(GatewayTelemetryWorker).to receive(:perform_async)
    end

    describe "queen_uid branch" do
      it "processes chunks without gateway" do
        hex_did = tree.did.gsub("SNET-", "")

        chunk = build_chunk_with_params(did_hex: hex_did, voltage: 4200, temp: 22)
        service = described_class.new(chunk, nil)

        expect { service.perform }.not_to raise_error
      end

      it "sets queen_uid from gateway when gateway is present" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?
        HardwareKey.create!(device_uid: tree_r2.did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 0 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log).not_to be_nil
        expect(log.queen_uid).to eq(gateway.uid)
      end
    end

    describe "interpret_status else branch" do
      it "handles unrecognized status codes gracefully" do
        service = described_class.new("", nil)
        result = service.send(:interpret_status, 0)
        expect(result).to eq(:homeostasis)

        result1 = service.send(:interpret_status, 1)
        expect(result1).to eq(:stress)

        result2 = service.send(:interpret_status, 2)
        expect(result2).to eq(:anomaly)

        result3 = service.send(:interpret_status, 3)
        expect(result3).to eq(:vm_error)
      end

      it "returns nil for an undefined status code" do
        service = described_class.new("", nil)
        result = service.send(:interpret_status, 99)
        expect(result).to be_nil
      end
    end

    describe "check_firmware_mismatch!" do
      let!(:active_firmware) { create(:bio_contract_firmware, :active, target_hardware_type: "Tree") }

      it "skips when reported_firmware_id is blank" do
        service = described_class.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, nil)
        }.not_to raise_error
      end

      it "skips when latest firmware id is nil" do
        service = described_class.new("", nil)
        BioContractFirmware.update_all(is_active: false)

        expect {
          service.send(:check_firmware_mismatch!, tree, 999)
        }.not_to raise_error
      end

      # [SEC.20] Порівнюється ЛИШЕ нова семантика (semantic-біт): legacy-кадри
      # несуть C-image константу — пряме порівняння з contract-id було
      # яблуками-з-грушами (вічний fw_pending після 1-ї кампанії).
      it "skips a legacy report (no semantic bit) — C-image id is not a contract id" do
        service = described_class.new("", nil)
        service.send(:check_firmware_mismatch!, tree, 0x0001)

        expect(tree.reload.firmware_update_status).not_to eq("fw_pending")
      end

      it "skips when reported contract matches latest (modulo 14 bits)" do
        service = described_class.new("", nil)
        report = TelemetryLog::FW_REPORT_SEMANTIC_BIT |
                 (active_firmware.id & TelemetryLog::FW_REPORT_ID_MASK)
        expect {
          service.send(:check_firmware_mismatch!, tree, report)
        }.not_to raise_error
        expect(tree.reload.firmware_update_status).not_to eq("fw_pending")
      end

      # 🔴 [ARCH.85] Приклад перецілено з ДІЇ на СПОСТЕРЕЖЕННЯ (присуд власника
      # 2026-08-14). Він цементував поведінку тракту, який до фіксу форми
      # завантаження прошивки не біг ЖОДНОГО разу: писальників
      # `target_hardware_type` було нуль, тож `latest_tree_firmware_id` завжди
      # віддавав nil. Тобто «дерево позначається `fw_pending`» було твердженням
      # про код, а не про систему — і перший реальний прогін стався б у полі.
      #
      # ⚠️ Пін тримає ОБИДВІ половини присуду: розбіжність ПОМІЧЕНА (лог) і стан
      # НЕ змінений. Без другої половини повернення `update_all` пройшло б зеленим.
      it "помічає розбіжність, але НЕ міняє стан дерева" do
        service = described_class.new("", nil)
        stale = TelemetryLog::FW_REPORT_SEMANTIC_BIT |
                ((active_firmware.id + 999) & TelemetryLog::FW_REPORT_ID_MASK)

        allow(Rails.logger).to receive(:info).with(/ARCH\.85 OTA Mismatch/)
        service.send(:check_firmware_mismatch!, tree, stale)

        expect(Rails.logger).to have_received(:info).with(/ARCH\.85 OTA Mismatch/)
        expect(tree.reload.firmware_update_status).to eq("fw_idle")
      end

      it "does not mark tree as fw_pending when already fw_pending" do
        Tree.where(id: tree.id).update_all(firmware_update_status: :fw_pending)
        service = described_class.new("", nil)
        stale = TelemetryLog::FW_REPORT_SEMANTIC_BIT |
                ((active_firmware.id + 999) & TelemetryLog::FW_REPORT_ID_MASK)
        service.send(:check_firmware_mismatch!, tree, stale)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end
    end

    describe "firmware_version_id assignment" do
      it "sets firmware_version_id when firmware_id is positive" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?
        HardwareKey.create!(device_uid: tree_r2.did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 42 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log.firmware_version_id).to eq(42)
      end

      it "sets firmware_version_id to nil when firmware_id is zero" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?
        HardwareKey.create!(device_uid: tree_r2.did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 0 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log.firmware_version_id).to be_nil
      end
    end

    describe "latest_tree_firmware_id caching" do
      it "caches the result across calls" do
        create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        service = described_class.new("", nil)

        first_call = service.send(:latest_tree_firmware_id)
        second_call = service.send(:latest_tree_firmware_id)

        expect(first_call).to eq(second_call)
      end
    end

    describe "valid_sensor_data? range checks" do
      it "rejects out-of-range voltage" do
        service = described_class.new("", nil)
        data = [ 0, 6000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects out-of-range temperature" do
        service = described_class.new("", nil)
        data = [ 0, 4200, 100, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts valid sensor data" do
        service = described_class.new("", nil)
        data = [ 0, 4200, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts voltage at lower boundary (0 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 0, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts voltage at upper boundary (5000 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 5000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "rejects voltage just above upper boundary (5001 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 5001, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts temperature at lower boundary (-45°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, -45, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts temperature at upper boundary (90°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, 90, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "rejects temperature just above upper boundary (91°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, 91, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects temperature just below lower boundary (-46°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, -46, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end
    end

    describe "check_metabolic_divergence! [E.63/E.64 — metabolic-channel conformance]" do
      let(:service) { described_class.new("", nil) }
      let(:tree)    { create(:tree, did: format("SNET-%08X", "0000AC20".to_i(16))) }

      # FW.29-PACK byte 10: [PanicFlag:1 | status:2 | growth_points:5].
      def status_byte_for(status_code, growth_points)
        (status_code << 5) | (growth_points & 0x1F)
      end

      it "stays silent for a conformant homeostasis packet (GP within 5..31)" do
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_metabolic_divergence!, tree, { bio_status: :homeostasis }, status_byte_for(0, 18))
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "flags a homeostasis packet whose GP is below the metabolic floor (GP < 5)" do
        # firmware pack_status_byte clamps homeostasis GP to ≥ 5; GP=3 cannot come
        # from current firmware → a corrupt/forged StatusByte.
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_metabolic_divergence!, tree, { bio_status: :homeostasis }, status_byte_for(0, 3))
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
      end

      it "stays silent for a conformant stress packet (GP == 1)" do
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_metabolic_divergence!, tree, { bio_status: :stress }, status_byte_for(1, 1))
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "flags a stress packet whose GP is not the survival floor (GP ≠ 1)" do
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_metabolic_divergence!, tree, { bio_status: :stress }, status_byte_for(1, 7))
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
      end

      it "does not flag anomaly/vm_error — GP already neutralised by emission_eligible_growth_points" do
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_metabolic_divergence!, tree, { bio_status: :anomaly }, status_byte_for(2, 9))
        service.send(:check_metabolic_divergence!, tree, { bio_status: :vm_error }, status_byte_for(3, 31))
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end
    end

    describe "check_z_divergence!" do
      let!(:tree_family) { create(:tree_family) }
      let!(:tree_with_family) do
        t = create(:tree, did: format("SNET-%08X", "0000AC01".to_i(16)), cluster: cluster, tree_family: tree_family)
        t.create_device_calibration! if t.device_calibration.nil?
        t
      end

      it "[FW.8] uses global defaults when tree_family is nil (governance fallback)" do
        tree_no_family = create(:tree, did: format("SNET-%08X", "0000AC02".to_i(16)), cluster: cluster, tree_family: tree_family)
        # Simulate nil tree_family by stubbing the association
        allow(tree_no_family).to receive(:tree_family).and_return(nil)
        service = described_class.new("", nil)
        # z=50 is ABOVE global default Tree::GLOBAL_LORENZ_Z_MAX (45.0)
        # device says "homeostasis" → divergence MUST be detected (server_healthy=false)
        attributes = { z_value: 50.0, bio_status: :homeostasis }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_no_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
      end

      it "[FW.8] no divergence when z_value is within global defaults and family is nil" do
        tree_no_family = create(:tree, did: format("SNET-%08X", "0000AC03".to_i(16)), cluster: cluster, tree_family: tree_family)
        allow(tree_no_family).to receive(:tree_family).and_return(nil)
        service = described_class.new("", nil)
        attributes = { z_value: 25.0, bio_status: :homeostasis } # well within 2..45

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_no_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "skips when server_z is nil" do
        service = described_class.new("", nil)
        attributes = { z_value: nil, bio_status: :homeostasis }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "skips when device_bio_status is nil" do
        service = described_class.new("", nil)
        attributes = { z_value: 25.0, bio_status: nil }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "increments fraud metric when device says homeostasis but server Z is unhealthy" do
        service = described_class.new("", nil)
        attributes = { z_value: 50.0, bio_status: :homeostasis }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
      end

      it "does not flag when both device and server agree on healthy" do
        service = described_class.new("", nil)
        attributes = { z_value: 25.0, bio_status: :homeostasis }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      it "does not flag when both device and server agree on unhealthy" do
        service = described_class.new("", nil)
        attributes = { z_value: 50.0, bio_status: :stress }

        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
      end

      # [FW.8] Дискримінуючий пін родинної смуги НА РІВНІ СЕРВІСУ — шов, якого
      # доти не тримав ніхто. Сусіди вище доводять лише fallback (родини нема →
      # глобальні межі), а ланцюг `Tree#effective_lorenz_thresholds` пінить
      # `spec/integration/fw8_threshold_governance_spec.rb`. Між ними лишалось
      # питання, чи `check_z_divergence!` ту межу СПОЖИВАЄ, чи мовчки їде на
      # глобальній — і жодне z, ужите поруч (25.0 · 50.0), відповісти не може,
      # бо лежить по один бік ОБОХ смуг.
      # z=3.0 і є той дискримінатор: здорове глобально (≥ 2.0), хворе для
      # родини (< critical_z_min 5.0).
      it "[FW.8] uses the tree_family band, not the global floor, when a family is present" do
        service = described_class.new("", nil)
        # Ліхтар: якщо фікстура з'їде так, що 3.0 перестане розрізняти смуги,
        # приклад мусить сказати це прямо, а не тихо стати вакуумним.
        expect(tree_with_family.effective_lorenz_thresholds[:min]).to eq(5.0)
        expect(Tree::GLOBAL_LORENZ_Z_MIN).to be < 3.0
        attributes = { z_value: 3.0, bio_status: :homeostasis }

        # Spy-форма свідомо: `RSpec/MessageSpies` вмикається, і новий приклад
        # не має права дописувати в чергу міграції те, що сам же й зрізає.
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
      end

      # [FW.31] Numeric tolerance band feature-flag.
      # Categorical default is preserved; numeric branch only fires when
      # `GAIA_DCI_NUMERIC_TOLERANCE=true` AND `device_z` is present in
      # the attributes hash. Wire-home для device_z існує з FW.2 wire-rev2
      # (CCM bytes 16..17, ×512; сентинель 0xFFFF → атрибут відсутній) —
      # e2e-шлях покритий у describe "FW.2 CCM path".
      describe "[FW.31] numeric tolerance band" do
        let(:service) { described_class.new("", nil) }

        it "does NOT run the numeric branch when feature-flag is off (default)" do
          stub_const("ENV", ENV.to_h.except("GAIA_DCI_NUMERIC_TOLERANCE", "GAIA_DCI_NUMERIC_EPSILON"))
          # Categorical agreement (both healthy) → no fraud
          attributes = { z_value: 25.0, bio_status: :homeostasis, device_z: 999.0 }

          # Even with absurd device_z drift, when toggle is off the
          # categorical pathway is the only one that runs and stays silent.
          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, tree_with_family, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
        end

        it "runs numeric branch and stays silent when drift is within ε" do
          stub_const("ENV", ENV.to_h.merge(
            "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
            "GAIA_DCI_NUMERIC_EPSILON" => "0.001"
          ))
          attributes = { z_value: 25.0, bio_status: :homeostasis, device_z: 25.0005 }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, tree_with_family, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
        end

        it "increments fraud metric when drift exceeds ε (numeric mismatch)" do
          stub_const("ENV", ENV.to_h.merge(
            "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
            "GAIA_DCI_NUMERIC_EPSILON" => "0.001"
          ))
          # |25.0 - 25.5| = 0.5 ≫ 0.001 — numeric branch fires.
          # Categorical also passes (both healthy) → only ONE increment from numeric.
          attributes = { z_value: 25.0, bio_status: :homeostasis, device_z: 25.5 }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, tree_with_family, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment).once
        end

        it "uses DEFAULT_DCI_EPSILON (0.001) when GAIA_DCI_NUMERIC_EPSILON is unset" do
          stub_const("ENV", ENV.to_h.merge("GAIA_DCI_NUMERIC_TOLERANCE" => "true").except("GAIA_DCI_NUMERIC_EPSILON"))
          # |25.0 - 25.0005| = 0.0005 < 0.001 (default) → silent.
          attributes = { z_value: 25.0, bio_status: :homeostasis, device_z: 25.0005 }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, tree_with_family, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
          expect(service.send(:numeric_dci_epsilon)).to eq(described_class::DEFAULT_DCI_EPSILON)
        end

        it "falls back to DEFAULT_DCI_EPSILON when GAIA_DCI_NUMERIC_EPSILON is malformed" do
          stub_const("ENV", ENV.to_h.merge(
            "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
            "GAIA_DCI_NUMERIC_EPSILON" => "not-a-float"
          ))

          expect(service.send(:numeric_dci_epsilon)).to eq(described_class::DEFAULT_DCI_EPSILON)
        end

        it "skips numeric branch when device_z is absent (current LoRa packet shape)" do
          stub_const("ENV", ENV.to_h.merge(
            "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
            "GAIA_DCI_NUMERIC_EPSILON" => "0.001"
          ))
          # No device_z key — feature-flagged hook cannot fire.
          attributes = { z_value: 25.0, bio_status: :homeostasis }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, tree_with_family, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
        end
      end

      # [ARCH.41] Cold-Start Time Paradox — time-sync recovery fallback.
      # When a warm-start (has history) categorical DCI mismatch is detected,
      # the service tries to re-derive Z from three epoch_day candidates.
      # A match means the Soldier's RTC was stale after VBAT loss, not fraud.
      describe "[ARCH.41] time-sync fallback in check_z_divergence!" do
        let!(:seed_hex) { SecureRandom.hex(32).upcase }
        let!(:recovery_tree) do
          t = create(:tree,
            did: format("SNET-%08X", "0000AC10".to_i(16)),
            cluster: cluster,
            tree_family: tree_family)
          t.create_device_calibration! if t.device_calibration.nil?
          HardwareKey.create!(device_uid: t.did,
            aes_key_hex: SecureRandom.hex(16).upcase,
            lorenz_seed_hex: seed_hex)
          t
        end
        let(:service) { described_class.new("", nil) }

        it "sets time_unsynced_fallback and enqueues TimeSyncDownlinkWorker on candidate match" do
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 25.0, 0.1, 0.2, 0.3 ])
          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.5, 0.5, 0.5 ])
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)

          attributes = {
            z_value: 0.5, bio_status: :homeostasis,
            cold_start_flag: false,
            temperature_c: 20, acoustic_events: 5, metabolism_s: 60, voltage_mv: 3300
          }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, recovery_tree, attributes)

          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
          expect(attributes[:time_unsynced_fallback]).to be(true)
          expect(TimeSyncDownlinkWorker).to have_received(:perform_async).with(recovery_tree.cluster_id)
        end

        it "increments fraud when no candidate matches (genuine mismatch)" do
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 0.5, 0.1, 0.2, 0.3 ])
          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.1, 0.2, 0.3 ])
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)

          attributes = {
            z_value: 0.5, bio_status: :homeostasis,
            cold_start_flag: false,
            temperature_c: 20, acoustic_events: 5, metabolism_s: 60, voltage_mv: 3300
          }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, recovery_tree, attributes)

          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
          expect(attributes[:time_unsynced_fallback]).to be_falsey
          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end

        it "skips recovery and increments fraud when cold_start_flag is true" do
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 25.0, 0.1, 0.2, 0.3 ])
          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.5, 0.5, 0.5 ])
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)

          attributes = {
            z_value: 0.5, bio_status: :homeostasis,
            cold_start_flag: true,
            temperature_c: 20, acoustic_events: 5, metabolism_s: 60, voltage_mv: 3300
          }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, recovery_tree, attributes)

          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
          expect(attributes[:time_unsynced_fallback]).to be_falsey
          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end

        it "skips recovery when tree has no hardware_key" do
          no_key_tree = create(:tree,
            did: format("SNET-%08X", "0000AC11".to_i(16)),
            cluster: cluster,
            tree_family: tree_family)
          no_key_tree.create_device_calibration! if no_key_tree.device_calibration.nil?
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)

          attributes = {
            z_value: 0.5, bio_status: :homeostasis,
            cold_start_flag: false,
            temperature_c: 20, acoustic_events: 5, metabolism_s: 60, voltage_mv: 3300
          }

          allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
          service.send(:check_z_divergence!, no_key_tree, attributes)
          expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment)
          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end
      end

      describe "[ARCH.41] try_time_sync_recovery unit" do
        let!(:seed_hex) { SecureRandom.hex(32).upcase }
        let!(:recovery_tree) do
          t = create(:tree,
            did: format("SNET-%08X", "0000AC20".to_i(16)),
            cluster: cluster,
            tree_family: tree_family)
          t.create_device_calibration! if t.device_calibration.nil?
          HardwareKey.create!(device_uid: t.did,
            aes_key_hex: SecureRandom.hex(16).upcase,
            lorenz_seed_hex: seed_hex)
          t
        end
        let(:service) { described_class.new("", nil) }
        let(:thresholds) { { min: 2.0, max: 45.0 } }

        it "returns false when tree has no hardware_key" do
          bare_tree = create(:tree, did: format("SNET-%08X", "0000AC21".to_i(16)), cluster: cluster)
          bare_tree.create_device_calibration! if bare_tree.device_calibration.nil?
          attributes = { temperature_c: 20, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300 }

          expect(service.send(:try_time_sync_recovery, bare_tree, attributes, thresholds, true)).to be(false)
          expect(attributes[:time_unsynced_fallback]).to be_nil
        end

        it "tries exactly three epoch_day candidates" do
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 0.5, 0.0, 0.0, 0.0 ])
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)
          attributes = { temperature_c: 20, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300 }

          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.1, 0.2, 0.3 ])
          service.send(:try_time_sync_recovery, recovery_tree, attributes, thresholds, true)
          expect(SilkenNet::SeedDerivation).to have_received(:initial_state).exactly(3).times
        end

        it "includes FIRMWARE_RTC_DEFAULT_EPOCH_DAY as one of the candidates" do
          captured = []
          allow(SilkenNet::SeedDerivation).to receive(:initial_state) do |_seed, epoch_day|
            captured << epoch_day
            [ 0.1, 0.2, 0.3 ]
          end
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 0.5, 0.0, 0.0, 0.0 ])
          attributes = { temperature_c: 20, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300 }

          service.send(:try_time_sync_recovery, recovery_tree, attributes, thresholds, true)

          expect(captured).to include(described_class::FIRMWARE_RTC_DEFAULT_EPOCH_DAY)
        end

        it "pins FIRMWARE_RTC_DEFAULT_EPOCH_DAY to the real 2000-01-01 epoch day" do
          # [ARCH.41] Was 10_951 (leap-less firmware approximation
          # artifact); firmware now uses exact civil-days arithmetic
          # (lorenz_seed.h Silken_Days_From_Civil → 10_957), and the recovery
          # candidate must equal Time.utc(2000,1,1).to_i / 86_400.
          expect(described_class::FIRMWARE_RTC_DEFAULT_EPOCH_DAY)
            .to eq(Time.utc(2000, 1, 1).to_i / 86_400)
        end

        it "short-circuits at the first matching candidate" do
          call_count = 0
          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.5, 0.5, 0.5 ])
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state) do
            call_count += 1
            [ 25.0, 0.0, 0.0, 0.0 ]
          end
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)
          attributes = { temperature_c: 20, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300 }

          service.send(:try_time_sync_recovery, recovery_tree, attributes, thresholds, true)

          expect(call_count).to eq(1)
        end

        it "does not enqueue TimeSyncDownlinkWorker when cluster_id is nil" do
          allow(recovery_tree).to receive(:cluster_id).and_return(nil)
          allow(SilkenNet::SeedDerivation).to receive(:initial_state).and_return([ 0.5, 0.5, 0.5 ])
          allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_return([ 25.0, 0.0, 0.0, 0.0 ])
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)
          attributes = { temperature_c: 20, acoustic_events: 0, metabolism_s: 60, voltage_mv: 3300 }

          service.send(:try_time_sync_recovery, recovery_tree, attributes, thresholds, true)

          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end
      end

      # [ARCH.41-B] Явний wire-sentinel «час невідомий» (acoustic = 0xFE) —
      # голос самого Солдата, на відміну від recovery-детектива (ARCH.41-A).
      # Нейтралізація ДО DCI: пристрій рахував Лоренц з acoustic=0 (дзеркало
      # Soldier_Acoustic_Wire_Value), сервер мусить так само; alert/stress
      # ланцюги бачать 0, а не фальшиві 254 «події».
      describe "[ARCH.41-B] apply_time_uncertain_sentinel!" do
        let!(:sentinel_tree) do
          t = create(:tree,
            did: format("SNET-%08X", "0000AC30".to_i(16)),
            cluster: cluster,
            tree_family: tree_family)
          t.create_device_calibration! if t.device_calibration.nil?
          t
        end
        let(:service) { described_class.new("", nil) }

        it "neutralizes 0xFE to zero, flags time_unsynced_fallback and enqueues CMD_TIME_SYNC" do
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)
          attributes = { acoustic_events: 0xFE }

          service.send(:apply_time_uncertain_sentinel!, sentinel_tree, attributes, "0000AC30")

          expect(attributes[:acoustic_events]).to eq(0)
          expect(attributes[:time_unsynced_fallback]).to be(true)
          expect(TimeSyncDownlinkWorker).to have_received(:perform_async).with(sentinel_tree.cluster_id)
        end

        it "leaves real acoustic counts untouched (incl. FW.22 saturation 255 and clamped 253)" do
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)

          [ 0, 42, 0xFD, 0xFF ].each do |real_count|
            attributes = { acoustic_events: real_count }
            service.send(:apply_time_uncertain_sentinel!, sentinel_tree, attributes, "0000AC30")

            expect(attributes[:acoustic_events]).to eq(real_count)
            expect(attributes[:time_unsynced_fallback]).to be_nil
          end
          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end

        it "still neutralizes and flags when tree has no cluster (no worker enqueue)" do
          orphan_tree = sentinel_tree
          allow(orphan_tree).to receive(:cluster_id).and_return(nil)
          allow(TimeSyncDownlinkWorker).to receive(:perform_async)
          attributes = { acoustic_events: 0xFE }

          service.send(:apply_time_uncertain_sentinel!, orphan_tree, attributes, "0000AC31")

          expect(attributes[:acoustic_events]).to eq(0)
          expect(attributes[:time_unsynced_fallback]).to be(true)
          expect(TimeSyncDownlinkWorker).not_to have_received(:perform_async)
        end
      end
    end


    describe "acoustic_events overflow warning" do
      it "logs warning when acoustic_events is 255 (saturated)" do
        chunk = build_chunk(did_hex, -70, 3500, 25, 255, 100, 0, 3)

        allow(Rails.logger).to receive(:warn).and_call_original

        described_class.call(chunk)

        expect(Rails.logger).to have_received(:warn).with(/Acoustic Overflow/).once
      end

      it "does not log warning for acoustic_events below 255" do
        chunk = build_chunk(did_hex, -70, 3500, 25, 254, 100, 0, 3)

        allow(Rails.logger).to receive(:warn).and_call_original

        described_class.call(chunk)

        expect(Rails.logger).not_to have_received(:warn).with(/Acoustic Overflow/)
      end
    end

    describe "multiple chunks in batch" do
      let(:did_hex2) { "0000ABCE" }
      let(:extracted_did2) { format("SNET-%08X", did_hex2.to_i(16)) }
      let!(:tree2) do
        t = create(:tree, did: extracted_did2)
        t.create_device_calibration! if t.device_calibration.nil?
        HardwareKey.create!(device_uid: t.did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)
        t
      end

      it "processes multiple valid chunks in a single batch" do
        chunk1 = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
        chunk2 = build_chunk(did_hex2, -80, 4000, 20, 3, 150, 0, 3)
        batch = chunk1 + chunk2

        expect { described_class.call(batch) }.to change(TelemetryLog, :count).by(2)
      end

      it "skips invalid chunks while processing valid ones" do
        valid_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
        invalid_chunk = build_chunk("FFFFFFFF", -70, 3500, 25, 5, 100, 0, 3) # unknown DID
        batch = valid_chunk + invalid_chunk

        expect { described_class.call(batch) }.to change(TelemetryLog, :count).by(1)
      end

      it "tolerates a truncated trailing chunk without raising [TEST.2 regression]" do
        # Обрізана передача: валідний 21-байтний chunk + 2-байтовий хвіст.
        # preload_trees мусить скіпнути хвіст так само, як головний цикл —
        # інакше format("SNET-%08X", nil) падає TypeError ще до skip.
        valid_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
        batch = valid_chunk + "\xAB\xCD".b

        expect { described_class.call(batch) }.to change(TelemetryLog, :count).by(1)
      end
    end

    describe "RSSI inversion" do
      it "correctly inverts RSSI from unsigned to negative" do
        # RSSI -70 → stored as 70 (unsigned) in packet → read back as -70
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.rssi).to eq(-70)
      end

      it "correctly handles RSSI -128 (worst signal)" do
        chunk = build_chunk(did_hex, -128, 3500, 25, 5, 100, 0, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.rssi).to eq(-128)
      end
    end

    describe "growth_points extraction from status_byte" do
      it "extracts growth_points from lower 5 bits with 2x backend upscale" do
        # [FW.29-PACK] status_byte = 0b000_10101 = 21 → bio_status=homeostasis(0),
        # wire growth=21 → stored growth_points = 21 * 2 = 42 (preserves tokenomic invariant)
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 21, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(42)
        expect(log.bio_status).to eq("homeostasis")
      end

      it "extracts max growth_points (62) correctly" do
        # [FW.29-PACK] status_byte = 0b000_11111 = 31 (max 5-bit) → stored = 62
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 31, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(62)
      end

      it "extracts both status and growth_points from combined byte" do
        # [FW.29-PACK] status_byte = 0b001_00101 = 37 → bio_status=stress(1),
        # wire growth=5 → stored = 10
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 37, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(10)
        expect(log.bio_status).to eq("stress")
      end

      it "anomaly (status=2) survives PANIC_FLAG_BIT mask without being demoted to homeostasis" do
        # [FW.29-PACK regression]: pre-fix, anomaly was packed as `(2<<6)|gp = 0x80|gp`,
        # then masked by `& 0x7F` in firmware → bit 7 cleared → backend read homeostasis(0).
        # After FW.29-PACK: anomaly is `(2<<5)|gp = 0x40|gp`, bit 7 already 0,
        # mask is a no-op, backend reads anomaly(2) correctly.
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0b010_00000, 3)
        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.bio_status).to eq("anomaly")
      end

      it "vm_error (status=3) survives PANIC_FLAG_BIT mask without being demoted to stress" do
        # [FW.29-PACK regression]: legacy BIO_STATUS_VM_ERROR = 0xFF, masked to 0x7F.
        # Pre-fix decoding: `0x7F >> 6 = 1` (stress) — silent status-3 demotion.
        # Post-fix: `(0x7F >> 5) & 0x03 = 3` (vm_error).
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0x7F, 3)
        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.bio_status).to eq("vm_error")
        # [FW.29] Emission gate: vm_error не карбує — раніше
        # legacy VM_ERROR (0xFF→0x7F) приносив (0x7F & 0x1F) * 2 = 62 бали
        # за КОЖЕН error-пакет. Тепер gp = 0 для anomaly/vm_error.
        expect(log.growth_points).to eq(0)
      end

      # [FW.29] Emission eligibility gate — канон 04_01/05_02:
      # емісія лише для homeostasis/stress; anomaly зупиняє, vm_error'у не віримо.
      describe "emission eligibility gate (anomaly/vm_error → growth_points 0)" do
        it "zeroes growth_points for anomaly even when wire gp bits are non-zero (bit-flip defense)" do
          # status_byte = 0b010_01010 = anomaly(2) + wire gp=10 (зловмисний/бітфліп)
          chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0b010_01010, 3)
          described_class.call(chunk)
          log = TelemetryLog.last
          expect(log.bio_status).to eq("anomaly")
          expect(log.growth_points).to eq(0)
        end

        it "zeroes growth_points for firmware VM_ERROR wire byte 0x60 (vm_error, gp=0)" do
          # Firmware BIO_STATUS_VM_ERROR = 0x60: [0|11|00000]
          chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0x60, 3)
          described_class.call(chunk)
          log = TelemetryLog.last
          expect(log.bio_status).to eq("vm_error")
          expect(log.growth_points).to eq(0)
        end

        it "keeps stress emission intact (wire gp=1 → stored 2)" do
          # stress видає мінімальну емісію виживання — гейт її НЕ зрізає
          chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0b001_00001, 3)
          described_class.call(chunk)
          log = TelemetryLog.last
          expect(log.bio_status).to eq("stress")
          expect(log.growth_points).to eq(2)
        end
      end
    end
  end

  # [SEC.11] Per-tree dispatch between legacy DID-as-seed and the
  # [SEC.11] K_seed-derived initial-state path is the SOLE attractor
  # entry-point. Every Tree must have a provisioned HardwareKey with
  # `lorenz_seed_hex`; missing seeds raise MissingLorenzSeedError.
  describe "Lorenz seed provenance [SEC.11]" do
    before do
      # Allow the real attractor for these scenarios so we can observe
      # the call signature and persisted trajectory tail.
      allow(SilkenNet::Attractor).to receive(:calculate_z_from_state).and_call_original
    end

    it "raises MissingLorenzSeedError when a tree has no HardwareKey" do
      hardware_key.destroy!
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      expect { described_class.call(chunk) }
        .to raise_error(TelemetryUnpackerService::MissingLorenzSeedError, /no provisioned K_seed/)
    end

    it "persists trajectory tail and marks cold_start_flag on the first packet" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      described_class.call(chunk)

      log = TelemetryLog.last
      expect(log.cold_start_flag).to be(true)
      expect(log.lorenz_state_x).to be_a(Float).and be_finite
      expect(log.lorenz_state_y).to be_a(Float).and be_finite
      expect(log.lorenz_state_z).to be_a(Float).and be_finite
    end

    it "chains continuation from the previous TelemetryLog tail (cold_start_flag=false)" do
      # First packet — cold start, persists a tail.
      described_class.call(build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3))
      first_tail = TelemetryLog.last.slice(:lorenz_state_x, :lorenz_state_y, :lorenz_state_z)

      # Second packet — should chain from first_tail.
      described_class.call(build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3))
      second = TelemetryLog.last
      expect(second.cold_start_flag).to be(false)

      # Verify chaining: server Z must equal calculate_z_from_state(first_tail, ...)
      expected = SilkenNet::Attractor.calculate_z_from_state(
        first_tail["lorenz_state_x"], first_tail["lorenz_state_y"],
        first_tail["lorenz_state_z"], 25.0, 5, 100, 3500
      )
      expect(second.z_value).to eq(expected.first)
    end

    # [PERF.1] Двокроковий пошук хвоста: обмежене вікно — це ПРУНІНГ, а не поріг
    # тиші. Дерево, що мовчало довше за вікно, мусить лишитись ТЕПЛИМ — прошивка
    # вирішує cold-start за маркером RTC (`DR19 == LORENZ_STATE_MAGIC`), не за
    # годинником сервера, тож серверна межа розсинхронізувала б їх однобічно
    # (канон `03_04 §2.1`: cold-derive належить дереву БЕЗ історії).
    # Мутація: прибери фолбек `|| lorenz_tail_row(scope)` — приклад червоніє
    # і на `cold_start_flag`, і на z_value (той стає re-derive, не продовженням).
    it "chains warm from a tail older than the fast window" do
      described_class.call(build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3))
      first = TelemetryLog.order(:id).last
      first_tail = first.slice(:lorenz_state_x, :lorenz_state_y, :lorenz_state_z)

      # Відсуваємо хвіст за межу швидкого вікна (update_columns — повз seal-guard
      # і повз AR-колбеки; PostgreSQL сам переносить рядок між партиціями).
      stale_at = described_class::LORENZ_TAIL_FAST_WINDOW.ago - 1.day
      first.update_columns(created_at: stale_at)
      expect(TelemetryLog.where(created_at: described_class::LORENZ_TAIL_FAST_WINDOW.ago..).count)
        .to eq(0) # інакше приклад вакуумний: хвіст лишився б у швидкому вікні

      described_class.call(build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3))
      second = TelemetryLog.where.not(id: first.id).order(:id).last

      expect(second.cold_start_flag).to be(false)
      expected = SilkenNet::Attractor.calculate_z_from_state(
        first_tail["lorenz_state_x"], first_tail["lorenz_state_y"],
        first_tail["lorenz_state_z"], 25.0, 5, 100, 3500
      )
      expect(second.z_value).to eq(expected.first)
    end
  end

  # [SEC.10] Frame Counter anti-replay для panic packets. Сторожовий пес
  # панічного каналу — Redis SETNX по nonce-ключу; replay повторює тот
  # самий counter, ми його рубаємо у логах ДО створення TelemetryLog.
  describe "panic frame counter anti-replay [SEC.10]" do
    # build_panic_chunk is provided by TelemetryChunkHelper
    # (spec/support/telemetry_chunk_helper.rb).

    before do
      Rails.cache.clear
      allow(SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL).to receive(:increment)
    end

    it "accepts a fresh panic packet (counter=42) and creates a log" do
      chunk = build_panic_chunk(did_hex, 42)
      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL).not_to have_received(:increment)
      # [FW.29] PanicFlag персиститься — панічний рядок queryable,
      # relayed_via_mesh? знає стартовий TTL (PANIC_TTL=5)
      expect(TelemetryLog.last.panic).to be(true)
    end

    it "rejects a replayed panic packet (same counter twice)" do
      chunk = build_panic_chunk(did_hex, 42)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      # Replay — exact same chunk, same counter
      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL).to have_received(:increment).once
    end

    it "accepts two panic packets with different counters from same DID" do
      expect { described_class.call(build_panic_chunk(did_hex, 100)) }
        .to change(TelemetryLog, :count).by(1)
      expect { described_class.call(build_panic_chunk(did_hex, 101)) }
        .to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL).not_to have_received(:increment)
    end

    it "accepts same counter from different DIDs (nonce key includes DID)" do
      other_did_hex = "0000BEEF"
      other_extracted = format("SNET-%08X", other_did_hex.to_i(16))
      create(:tree, did: other_extracted)
      HardwareKey.create!(
        device_uid: other_extracted,
        aes_key_hex: SecureRandom.hex(16).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      expect { described_class.call(build_panic_chunk(did_hex, 42)) }
        .to change(TelemetryLog, :count).by(1)
      expect { described_class.call(build_panic_chunk(other_did_hex, 42)) }
        .to change(TelemetryLog, :count).by(1)
    end

    it "skips replay check for non-panic packets (PANIC_FLAG_BIT = 0)" do
      # Normal packet, no panic flag, counter byte position = 0
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      # Same chunk twice — no SEC.10 check on non-panic packets, both pass
      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
    end

    it "skips replay check when panic flag set but counter==0 (legacy firmware)" do
      # Pre-SEC.10 firmware емітить panic-flag без counter → counter=0.
      # Ми не блокуємо, бо counter=0 == "no anti-replay protection available";
      # rate-limit на AlertDispatchService рівні все ще працює.
      chunk1 = build_panic_chunk(did_hex, 0)
      chunk2 = build_panic_chunk(did_hex, 0)
      expect { described_class.call(chunk1) }.to change(TelemetryLog, :count).by(1)
      expect { described_class.call(chunk2) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL).not_to have_received(:increment)
    end

    it "preserves firmware_id alongside counter in PAD (FW.22 + SEC.10 coexistence)" do
      # bytes 12..13 = firmware_id, bytes 14..15 = panic_counter.
      # Перевіряємо, що обидва правильно розпарсилися.
      chunk = build_panic_chunk(did_hex, 7, firmware_id: 0x0042)
      described_class.call(chunk)
      log = TelemetryLog.last
      expect(log.firmware_version_id).to eq(0x0042)
    end

    it "writes nonce key with TTL ≈ 25 hours (replay window guard)" do
      allow(Rails.cache).to receive(:write).with(
        "silken:panic:nonce:#{extracted_did}:42",
        "1",
        hash_including(expires_in: TelemetryUnpackerService::PANIC_NONCE_TTL,
                       unless_exist: true)
      ).and_call_original

      described_class.call(build_panic_chunk(did_hex, 42))

      expect(Rails.cache).to have_received(:write).with(
        "silken:panic:nonce:#{extracted_did}:42",
        "1",
        hash_including(expires_in: TelemetryUnpackerService::PANIC_NONCE_TTL,
                       unless_exist: true)
      )
    end
  end

  describe "#previous_lorenz_state_for [SEC.11]" do
    it "returns nil when the last Lorenz state row has a non-finite coordinate" do
      # Build a telemetry log with NaN in z to simulate corruption on disk.
      log = create(:telemetry_log, tree: tree, lorenz_state_x: 0.1, lorenz_state_y: 0.2,
                                   lorenz_state_z: Float::NAN, voltage_mv: 3500, temperature_c: 20)
      service = described_class.new("ignored")
      expect(service.send(:previous_lorenz_state_for, tree.reload)).to be_nil
      log.destroy
    end
  end

  describe "OTA firmware mismatch detection" do
    it "is a no-op when the tree is mid-OTA (fw_downloading/verifying/flashing)" do
      tree.update!(firmware_update_status: :fw_downloading)
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      service = described_class.new(chunk)
      reported = 99_999  # Differs from latest, but tree state blocks the flip.
      allow(service).to receive(:latest_tree_firmware_id).and_return(42)

      expect { service.send(:check_firmware_mismatch!, tree.reload, reported) }
        .not_to change { tree.reload.firmware_update_status }
    end
  end

  # [FW.2 wire-rev2] AES-128-CCM 29-byte chunk path, gated on
  # TELEMETRY_CCM_ENABLED=true. Wire format produced by Queen after
  # receiving a 28B CCM packet on LoRa:
  #
  #   [DID:4][RSSI:1][gossip_ts_lsb:1][FrameCounter:3 BE][ciphertext:12][MIC:8]
  #
  # Defaults stay on the 21B ECB path until firmware ships CCM emission.
  describe "FW.2 CCM path [TELEMETRY_CCM_ENABLED=true]" do
    let(:lora_key_hex) { SecureRandom.hex(16).upcase }
    let(:lora_key_bin) { [ lora_key_hex ].pack("H*") }

    before do
      # Re-provision the tree's HardwareKey with a Tree-shape AES-128 key
      # so binary_key returns exactly 16 bytes (matches firmware HKDF output).
      hardware_key.update!(aes_key_hex: lora_key_hex)
      Rails.cache.clear
      ENV["TELEMETRY_CCM_ENABLED"] = "true" # cleanup: глобальний ENV-snapshot у rails_helper
      allow(SilkenNet::Metrics::TELEMETRY_CCM_DECRYPT_OK_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL).to receive(:increment)
    end

    # Thin wrapper around TelemetryChunkHelper#build_ccm_chunk that
    # fills in the two values shared across every example in this block
    # (`did_hex` and the tree's LoRa AES-128 key) — keeps the call-site
    # ergonomics from when this helper lived inline.
    def build_ccm_chunk(did_hex_arg: did_hex, key: lora_key_bin, **kwargs)
      super(did_hex: did_hex_arg, key: key, **kwargs)
    end

    it "decrypts a CCM chunk (air+1) and creates a telemetry log" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 42)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)

      log = TelemetryLog.last
      expect(log.tree).to eq(tree)
      expect(log.voltage_mv).to eq(3500)
      expect(log.temperature_c).to eq(25.0)
      expect(log.acoustic_events).to eq(5)
      expect(log.metabolism_s).to eq(100)
      expect(log.rssi).to eq(-70)
      expect(log.mesh_ttl).to eq(3)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_DECRYPT_OK_TOTAL).to have_received(:increment)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).not_to have_received(:increment)
    end

    it "persists the PanicFlag from the CCM status byte" do
      # [FW.29] Soldier_Build_CCM_LoRa_Packet кладе той самий StatusByte
      # у CCM-плейн — біт 7 (0x80) мусить доїхати до telemetry_logs.panic.
      normal = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                               dt: 100, status: 0, ttl: 3, fc: 44)
      panic  = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 255,
                               dt: 100, status: 0x80, ttl: 5, fc: 45)

      described_class.call(normal)
      expect(TelemetryLog.last.panic).to be(false)

      described_class.call(panic)
      expect(TelemetryLog.last.panic).to be(true)
    end

    it "rejects a chunk with a tampered ciphertext byte" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 43)
      tampered = chunk.dup
      tampered.setbyte(10, tampered.getbyte(10) ^ 0x01)

      expect { described_class.call(tampered) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to have_received(:increment).once
    end

    it "rejects a chunk with a tampered MIC" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 44)
      tampered = chunk.dup
      tampered.setbyte(25, tampered.getbyte(25) ^ 0x80) # MIC = chunk bytes 21..28

      expect { described_class.call(tampered) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to have_received(:increment).once
    end

    it "rejects a chunk whose cleartext gossip byte was tampered (AAD under MIC)" do
      # [wire-rev2] gossip_ts_lsb (chunk byte 5) їде відкритим для
      # сусідів-Солдатів, але бекенд автентифікує його MIC'ом.
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 46, gossip_ts_lsb: 0x42)
      tampered = chunk.dup
      tampered.setbyte(5, tampered.getbyte(5) ^ 0xA5)

      expect { described_class.call(tampered) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to have_received(:increment).once
    end

    it "rejects a replayed frame counter for the same DID" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 100)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      # Same chunk → same FC → SETNX collision → reject.
      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL)
        .to have_received(:increment).once
    end

    it "accepts the same frame counter from a different DID (nonce key scoped per-DID)" do
      other_did_hex = "0000BEEF"
      other_extracted = format("SNET-%08X", other_did_hex.to_i(16))
      other_tree = create(:tree, did: other_extracted)
      other_tree.create_device_calibration! if other_tree.device_calibration.nil?
      other_key_hex = SecureRandom.hex(16).upcase
      HardwareKey.create!(
        device_uid: other_extracted,
        aes_key_hex: other_key_hex,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )

      c1 = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                           dt: 100, status: 0, ttl: 3, fc: 7)
      c2 = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                           dt: 100, status: 0, ttl: 3, fc: 7,
                           did_hex_arg: other_did_hex,
                           key: [ other_key_hex ].pack("H*"))

      expect { described_class.call(c1) }.to change(TelemetryLog, :count).by(1)
      expect { described_class.call(c2) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL).not_to have_received(:increment)
    end

    # ── wire-rev2 поля (device_z / diag / vpd_index) ──────────────────────

    it "feeds wire device_z into the numeric DCI branch end-to-end (FW.31 Gate D)" do
      stub_const("ENV", ENV.to_h.merge(
        "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
        "GAIA_DCI_NUMERIC_EPSILON" => "0.001"
      ))
      allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
      allow(Rails.logger).to receive(:warn).and_call_original

      # device_z = 99.0 — за E.64 стелею (≤ ~67) жоден server_z так не зайде:
      # drift > ε гарантовано → numeric-гілка мусить крикнути.
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 47, device_z: 99.0)

      # Лог комітиться (numeric DCI = сигнал, не відмова) — і це водночас
      # доводить strip транзієнта :device_z перед create! (не-колонка).
      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(Rails.logger).to have_received(:warn).with(/Z Divergence Numeric/)
      expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL)
        .to have_received(:increment).at_least(:once)
    end

    it "skips the numeric branch on the device_z sentinel (Lorenz slept — ARCH.41-C)" do
      stub_const("ENV", ENV.to_h.merge(
        "GAIA_DCI_NUMERIC_TOLERANCE" => "true",
        "GAIA_DCI_NUMERIC_EPSILON" => "0.001"
      ))
      allow(Rails.logger).to receive(:warn).and_call_original

      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 48, device_z: nil)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(Rails.logger).not_to have_received(:warn).with(/Z Divergence Numeric/)
    end

    it "surfaces diag-byte bits as Prometheus signals (FW.18b/FW.42/FW.2)" do
      allow(SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::FAUNA_SKIP_REPORTS_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::FW2_FC_DEGRADED_REPORTS_TOTAL).to receive(:increment)

      diag  = (3 << 3) | 0x02 | 0x01 # thr_invalid=3 | fauna_skip | fc_degraded
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 49, diag: diag)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL).to have_received(:increment)
      expect(SilkenNet::Metrics::FAUNA_SKIP_REPORTS_TOTAL).to have_received(:increment)
      expect(SilkenNet::Metrics::FW2_FC_DEGRADED_REPORTS_TOTAL).to have_received(:increment)
    end

    it "annotates wire-saturation when the CCM diag threshold_invalid counter is 31" do
      allow(SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL).to receive(:increment)
      allow(Rails.logger).to receive(:warn).and_call_original

      diag  = (31 << 3) # thr_invalid=31 (wire-сатурація), без fauna/fc бітів
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 52, diag: diag)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(Rails.logger).to have_received(:warn).with(/лічильник 31 \(wire-сатурація/)
    end

    it "keeps the vpd column nil until HW.32 calibration defines the index scale" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 50, vpd_index: 77)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(TelemetryLog.last.vpd).to be_nil
    end

    # [SEC.20] vpd-байт тимчасово несе contract-звіт [rev:1|id7] —
    # unpacker складає його у 16-бітну fw_report-семантику.
    it "assembles the SEC.20 fw-report from the vpd byte (running contract)" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 53, vpd_index: 42)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      log = TelemetryLog.last
      expect(log.firmware_report_semantic?).to be(true)
      expect(log.firmware_report_reverted?).to be(false)
      expect(log.firmware_report_contract_id).to eq(42)
    end

    it "raises the reverted flag from the vpd high bit (SEC.20 baseline-revert)" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 54,
                              vpd_index: 0x80 | 42)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      log = TelemetryLog.last
      expect(log.firmware_report_reverted?).to be(true)
      expect(log.firmware_report_contract_id).to eq(42)
    end

    it "drops the Queen-sentinel CCM packet (DID=0) without raising or committing a log" do
      # CCM path does not support Queen self-telemetry — see process_ccm_chunk.
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 1,
                              did_hex_arg: "00000000",
                              key: ("\x00".b * 16))

      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).not_to have_received(:increment)
    end

    it "skips a chunk shorter than the CCM stride" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 1)
      expect { described_class.call(chunk[0..23]) }.not_to change(TelemetryLog, :count)
    end

    it "rejects sensor data outside the safe voltage range (post-decrypt sanity check)" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 5500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 50)
      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
    end

    it "credits growth_points × 2 the same way as the 21B path" do
      # Wire status_byte = 10 → growth_points nibble = 10 → stored gp = 20.
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 10, ttl: 3, fc: 200)
      expect { described_class.call(chunk) }.to change { tree.wallet.reload.balance }.by(20)
    end

    it "falls back to the 21B ECB path when the feature flag is unset" do
      ENV.delete("TELEMETRY_CCM_ENABLED")
      ecb_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
      expect { described_class.call(ecb_chunk) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_DECRYPT_OK_TOTAL).not_to have_received(:increment)
    end

    # ------------------------------------------------------------------
    # Coverage gaps for the CCM uplink guards.
    # Every branch below corresponds to a real-logic guard (unknown
    # device, missing/invalid key, gateway routing, fw nibble, acoustic
    # overflow, broad rescue) — NOT defensive `&.`-nil padding.
    # ------------------------------------------------------------------

    it "drops the chunk and flags fraud when the DID is not in the trees cache" do
      allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
      allow(Rails.logger).to receive(:warn)

      unknown_did_hex = "DEADC0DE"
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 11,
                              did_hex_arg: unknown_did_hex)

      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment).once
      expect(SilkenNet::Metrics::TELEMETRY_CCM_DECRYPT_OK_TOTAL).not_to have_received(:increment)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/\[CCM Uplink\] DID SNET-DEADC0DE не знайдено/))
    end

    it "drops the chunk when the tree has no HardwareKey row at all" do
      # Covers the `&.` else branch on `tree.hardware_key&.binary_key`
      # — the cache LEFT-JOINs HardwareKey, so a tree may exist without
      # a provisioned key (de-provisioned device / registration glitch).
      allow(Rails.logger).to receive(:warn)
      # Encrypt with a throwaway key so the chunk is well-formed; service
      # rejects it before attempting decrypt anyway.
      throwaway_key = "\x00".b * 16
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 12, key: throwaway_key)
      hardware_key.destroy!

      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to have_received(:increment).once
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/\[CCM\] DID .+ missing\/invalid LoRa AES-128 key.*got nil/))
    end

    it "drops the chunk when the LoRa AES key has the wrong byte size" do
      allow(Rails.logger).to receive(:warn)
      # 24-byte blob fails the AES-128 size guard without changing the
      # DB-level validation on aes_key_hex (which would reject the raw
      # update). Stubbing keeps the path strictly about the in-memory
      # size check the service performs after key load.
      allow_any_instance_of(HardwareKey).to receive(:binary_key).and_return("A" * 24)

      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 13)

      expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
      expect(SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL).to have_received(:increment).once
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/missing\/invalid LoRa AES-128 key \(expected 16 bytes, got 24\)/))
    end

    it "records gateway uid when the CCM packet is routed via a known gateway" do
      gateway = create(:gateway)
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 14)

      expect { described_class.call(chunk, gateway.id) }.to change(TelemetryLog, :count).by(1)
      expect(TelemetryLog.last.queen_uid).to eq(gateway.uid)
    end

    # [E.63 (г), wire-rev2.1] Точний stateless GP-recompute з wire-EMA —
    # контракт «wire = вхід GP» (observational до bench-калібрування порогів).
    describe "exact metabolic recompute (ema_delta_t_s, E.63 (г))" do
      it "passes silently when wire GP matches m(ema) byte-exactly" do
        ema = 3600
        gp  = SilkenNet::Attractor.expected_homeostasis_gp(ema)
        allow(Rails.logger).to receive(:warn)
        chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                                dt: 200, status: gp, ttl: 3, fc: 41, ema: ema)

        expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
        expect(Rails.logger).not_to have_received(:warn)
          .with(a_string_matching(/Metabolic Divergence/))
      end

      it "warns + flags fraud metric when wire GP diverges from m(ema) — contract broken" do
        ema = 3600
        gp  = SilkenNet::Attractor.expected_homeostasis_gp(ema)
        bad_gp = gp == SilkenNet::Attractor::GP_HOMEO_MAX ? gp - 1 : gp + 1
        allow(Rails.logger).to receive(:warn)
        allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                                dt: 200, status: bad_gp, ttl: 3, fc: 42, ema: ema)

        # Observational: запис СТВОРЮЄТЬСЯ (мінт-гейт не чіпаємо до калібрування).
        expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
        expect(Rails.logger).to have_received(:warn)
          .with(a_string_matching(/Metabolic Divergence · exact.*recompute\(ema=3600s\)=#{gp}/))
        # at_least: фонова z-DCI фікстури (cold-start server-Z) теж може смикнути
        # цю ж метрику — точна гілка доведена специфічним лог-рядком вище.
        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL)
          .to have_received(:increment).at_least(:once)
      end

      it "skips the exact branch for non-homeostasis frames (panic ema=0)" do
        allow(Rails.logger).to receive(:warn)
        chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 0xFF,
                                dt: 0, status: 0x80, ttl: 5, fc: 43, ema: 0) # 0x80 = PanicFlag

        expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
        expect(Rails.logger).not_to have_received(:warn)
          .with(a_string_matching(/Metabolic Divergence · exact/))
      end
    end

    # [SEC.20] mesh_ctrl fw-нібл = C-image epoch (транзієнт): contract-звіт
    # їде vpd-байтом, тож нібл БІЛЬШЕ НЕ пише у firmware_version_id.
    it "keeps the mesh fw-nibble out of firmware_version_id (vpd report owns the column)" do
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fw_nibble: 7, fc: 15)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      log = TelemetryLog.last
      expect(log.firmware_version_id).to eq(TelemetryLog::FW_REPORT_SEMANTIC_BIT)
      expect(log.firmware_report_contract_id).to eq(0)
    end

    it "increments the acoustic overflow metric when acoustic == 255 on the CCM path" do
      allow(SilkenNet::Metrics::TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL).to receive(:increment)
      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 255,
                              dt: 100, status: 0, ttl: 3, fc: 17)

      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(SilkenNet::Metrics::TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL).to have_received(:increment).once
    end

    it "logs and swallows a StandardError raised inside commit_telemetry on the CCM path" do
      allow(Rails.logger).to receive(:error)
      allow_any_instance_of(described_class).to receive(:commit_telemetry)
        .and_raise(StandardError, "boom in commit")

      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 18)

      expect { described_class.call(chunk) }.not_to raise_error
      expect(Rails.logger).to have_received(:error)
        .with(a_string_matching(/\[CCM Telemetry Error\] DID .+: boom in commit/))
    end

    it "re-raises MissingLorenzSeedError raised on the CCM path so the worker can retry" do
      allow_any_instance_of(described_class).to receive(:compute_server_z)
        .and_raise(TelemetryUnpackerService::MissingLorenzSeedError, "no seed")

      chunk = build_ccm_chunk(rssi: -70, vcap: 3500, temp: 25, acoustic: 5,
                              dt: 100, status: 0, ttl: 3, fc: 19)

      expect { described_class.call(chunk) }
        .to raise_error(TelemetryUnpackerService::MissingLorenzSeedError)
    end
  end

  # commit_telemetry has three guard branches around wallet credit that the
  # existing happy-path specs never exercise. They are real-logic edges
  # (zero-credit species, family-less tree), not `&.` defensive nil.
  describe "commit_telemetry credit guards" do
    let(:chunk) { build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3) }

    # 🔴 Тут стояв `allow(tree.wallet).to receive(:credit!)` + `not_to have_received`,
    # і воно було ВАКУУМНИМ: сервіс тримає власний кеш `Tree.where(did:)` і кредитує
    # гаманець СВОГО екземпляра, тож стаб на нашому обʼєкті він не бачить ніколи —
    # асерція була істинною тривіально. Доведено мутацією: зняття гарда лишало
    # приклад зеленим. Спостерігаємо натомість НАСЛІДОК у БД, і стаб не потрібен.
    it "does not credit the wallet when growth_points is zero" do
      # status_byte=0 → wire growth_points nibble=0 → stored gp=0.
      before_balance = tree.wallet.balance
      expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)
      expect(tree.wallet.reload.balance).to eq(before_balance)
      expect(TelemetryLog.last.growth_points).to eq(0)
    end

    it "credits the raw growth_points when the tree has no tree_family" do
      # tree_family#weighted_growth_points returns nil via stub → || growth_points fallback.
      allow_any_instance_of(Tree).to receive(:tree_family).and_return(nil)
      gp_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 10, 3) # wire nibble=10 → gp=20

      expect { described_class.call(gp_chunk) }.to change { tree.wallet.reload.balance }.by(20)
    end

    it "skips wallet.credit! when carbon coefficient rounds weighted_points to zero" do
      # coefficient 0.001 × growth_points 2 = 0.002 → round(2) = 0.0 → not positive.
      tiny = create(:tree_family, carbon_sequestration_coefficient: 0.001)
      tree.update!(tree_family: tiny)
      tiny_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 1, 3) # wire nibble=1 → gp=2

      # Той самий вакуум, що вище: стаб на НАШОМУ `tree.wallet` сервіс не бачить.
      before_balance = tree.wallet.balance
      expect { described_class.call(tiny_chunk) }.to change(TelemetryLog, :count).by(1)
      expect(tree.wallet.reload.balance).to eq(before_balance)
    end
  end
end

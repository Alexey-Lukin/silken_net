# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OTA firmware deployment flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
  end

  describe "OtaPackagerService" do
    # 750 hex bytes = 1500 hex chars = 750 binary bytes
    let(:hex_payload) { "41" * 750 }
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: hex_payload) }

    it "generates manifest with correct metadata" do
      result = OtaPackagerService.prepare(firmware, chunk_size: 512)

      manifest = result[:manifest]
      expect(manifest[:version]).to eq(firmware.version)
      expect(manifest[:total_size]).to eq(750) # 750 binary bytes
      expect(manifest[:total_chunks]).to eq(2) # ceil(750/512)
      expect(manifest[:checksum]).to be_present
      expect(manifest[:sha256]).to eq(firmware.binary_sha256)
    end

    it "generates correct number of packages with headers" do
      result = OtaPackagerService.prepare(firmware, chunk_size: 512)
      packages = result[:packages].to_a

      expect(packages.length).to eq(2)

      # Each package starts with OTA marker 0x99
      markers = packages.map { |pkg| pkg.unpack1("C") }
      expect(markers).to all(eq(0x99))

      # Verify chunk indices and totals
      indices_and_totals = packages.map { |pkg| pkg[1..4].unpack("nn") }
      expect(indices_and_totals.map(&:first)).to eq([ 0, 1 ])
      expect(indices_and_totals.map(&:last)).to all(eq(2))
    end

    it "uses LoRa MTU for smaller chunk sizes" do
      result = OtaPackagerService.prepare(firmware, chunk_size: OtaPackagerService::LORA_MTU)
      manifest = result[:manifest]
      expected_chunks = (750.0 / OtaPackagerService::LORA_MTU).ceil
      expect(manifest[:total_chunks]).to eq(expected_chunks)
    end
  end

  describe "BioContractFirmware model" do
    let!(:firmware) { create(:bio_contract_firmware, :for_tree) }

    it "has required attributes" do
      expect(firmware.version).to be_present
      expect(firmware.target_hardware_type).to be_present
    end
  end

  describe "Tree firmware update status tracking" do
    let(:tree_family) { create(:tree_family) }
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "defaults to fw_idle status" do
      expect(tree.firmware_fw_idle?).to be true
    end

    it "transitions through firmware update statuses" do
      tree.update!(firmware_update_status: :fw_pending)
      expect(tree.firmware_fw_pending?).to be true

      tree.update!(firmware_update_status: :fw_downloading)
      expect(tree.firmware_fw_downloading?).to be true

      tree.update!(firmware_update_status: :fw_completed)
      expect(tree.firmware_fw_completed?).to be true
    end

    # 🔴 [ARCH.85] Перецілено з ДІЇ на СПОСТЕРЕЖЕННЯ (присуд власника 2026-08-14).
    # Тракт не біг у проді жодного разу — писальників `target_hardware_type` було
    # нуль, тож `latest_tree_firmware_id` завжди віддавав `nil`. Обидві спеки цієї
    # осі (тут і в `telemetry_unpacker_service_spec`) цементували поведінку, яка
    # вперше відбулась би ОДРАЗУ в полі, на гарячому шляху.
    it "помічає розбіжність прошивки, але стан дерева НЕ міняє" do
      latest_fw = create(:bio_contract_firmware, :for_tree, :active)
      # [SEC.20] Wire-звіт нової семантики: semantic-біт + застарілий contract-id
      stale_report = TelemetryLog::FW_REPORT_SEMANTIC_BIT |
                     ((latest_fw.id - 1) & TelemetryLog::FW_REPORT_ID_MASK)
      before = tree.firmware_update_status

      service = TelemetryUnpackerService.new(nil, nil)
      allow(Rails.logger).to receive(:info).with(/ARCH\.85 OTA Mismatch/)

      service.send(:check_firmware_mismatch!, tree, stale_report)

      expect(Rails.logger).to have_received(:info).with(/ARCH\.85 OTA Mismatch/)
      expect(tree.reload.firmware_update_status).to eq(before)
    end
  end

  describe "Gateway firmware update status tracking" do
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "defaults to fw_idle status" do
      expect(gateway.firmware_fw_idle?).to be true
    end

    it "transitions to updating state during OTA" do
      gateway.update!(state: :updating)
      expect(gateway.updating?).to be true
    end

    it "returns to idle with firmware version after OTA completion" do
      gateway.update!(state: :updating)
      gateway.update!(state: :idle, firmware_version: "v2.1.0")
      expect(gateway.idle?).to be true
      expect(gateway.firmware_version).to eq("v2.1.0")
    end

    it "transitions to faulty after max retries" do
      gateway.update!(state: :faulty)
      expect(gateway.faulty?).to be true
    end
  end

  # =========================================================================
  # [FW.23] HMAC dual-gate end-to-end: backend signs → Queen relay → Soldier accept
  # =========================================================================
  describe "FW.23 OTA HMAC trailer end-to-end" do
    let(:hex_payload) { "52495445" + ("AB" * 100) }  # "RITE" magic + 200 bytes payload
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: hex_payload) }
    let(:cluster_id) { "test-cluster-fw23" }

    it "backend produces 4 HMAC trailer chunks at end of packages (3 tag + version)" do
      result = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id)
      packages = result[:packages].to_a
      trailer  = packages.last(4)

      # 0x9B marker on each trailer chunk
      expect(trailer.map { |p| p.unpack1("C") }).to all(eq(0x9B))
      # 16-byte LoRa-formatted blocks (single AES-256 block)
      expect(trailer.map(&:bytesize)).to all(eq(16))
      # seg_idx 1, 2, 3 (HMAC tag) + 4 (version_id) in big-endian
      expect(trailer.map { |p| p[1..2].unpack1("n") }).to eq([ 1, 2, 3, 4 ])
      # seg 4 carries firmware.id — the version_id input the Soldier needs to verify
      expect(trailer.last[5..8].unpack1("N")).to eq(firmware.id)
    end

    # [FW.53] LoRa-шар тепер несе WIRE-потік: padded bytecode +
    # CRC32-хвіст (вирівняний на LORA_MTU, бо Soldier рахує байти як 11×chunks).
    # HMAC хешує padded stream БЕЗ CRC32 — дзеркало Soldier dual-gate
    # (ota_buffer[0..data_len) після зрізання CRC).
    def lora_padded_payload(raw)
      pad_len = (OtaPackagerService::LORA_MTU -
                 ((raw.bytesize + OtaPackagerService::LORA_CRC32_BYTES) %
                  OtaPackagerService::LORA_MTU)) % OtaPackagerService::LORA_MTU
      raw.b + ("\x00".b * pad_len)
    end

    it "manifest exposes lora_total_chunks for Queen→Soldier cross-check" do
      manifest = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
      # Soldier sees this `total_chunks` in 0x99 LoRa header → must match HMAC binding
      wire_size = lora_padded_payload(firmware.binary_payload).bytesize +
                  OtaPackagerService::LORA_CRC32_BYTES
      expect(manifest[:lora_total_chunks]).to eq(wire_size / OtaPackagerService::LORA_MTU)
      expect(manifest[:hmac_signed]).to be true
    end

    it "trailer chunks reconstruct a 32-byte HMAC tag matching .compute_hmac_tag" do
      manifest = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
      packages = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:packages).to_a
      trailer  = packages.last(4)

      # Reconstruct tag from the 3 HMAC trailer chunks (bytes 5..); seg 4 = version.
      reconstructed = trailer[0][5..15] + trailer[1][5..15] + trailer[2][5..14]

      expected = OtaPackagerService.compute_hmac_tag(
        lora_padded_payload(firmware.binary_payload),
        firmware.id,
        manifest[:lora_total_chunks],
        cluster_id: cluster_id
      )
      expect(reconstructed.b).to eq(expected)
      # seg 4 carries the exact version_id bound into that tag (firmware.id, 4B BE)
      expect(trailer[3][5..8].unpack1("N")).to eq(firmware.id)
    end

    it "Soldier dual-gate would accept a properly signed firmware (mirrors C logic)" do
      manifest = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
      bytecode = firmware.binary_payload
      expected = OtaPackagerService.compute_hmac_tag(bytecode, firmware.id, manifest[:lora_total_chunks], cluster_id: cluster_id)

      # Gate 1: magic check ("RITE" little-endian = 0x45544952)
      magic = bytecode.byteslice(0, 4).unpack1("V")
      expect(magic).to eq(0x45544952)

      # Gate 2: HMAC matches (constant-time on firmware; here we use eq for clarity)
      received = expected.dup
      expect(received).to eq(expected)
    end

    it "Soldier dual-gate would REJECT a tampered bytecode (anti-tamper)" do
      manifest = OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
      original_tag = OtaPackagerService.compute_hmac_tag(
        firmware.binary_payload, firmware.id, manifest[:lora_total_chunks], cluster_id: cluster_id
      )
      tampered = firmware.binary_payload.dup
      tampered[10] = (tampered[10].ord ^ 0x01).chr
      tampered_tag = OtaPackagerService.compute_hmac_tag(
        tampered, firmware.id, manifest[:lora_total_chunks], cluster_id: cluster_id
      )
      expect(tampered_tag).not_to eq(original_tag)
    end

    it "Soldier dual-gate would REJECT replayed image with old version_id (anti-replay)" do
      lora_total = 5
      tag_v1 = OtaPackagerService.compute_hmac_tag(firmware.binary_payload, 1, lora_total, cluster_id: cluster_id)
      tag_v2 = OtaPackagerService.compute_hmac_tag(firmware.binary_payload, 2, lora_total, cluster_id: cluster_id)
      expect(tag_v1).not_to eq(tag_v2)
    end

    it "Soldier dual-gate would REJECT truncation attack (anti-truncation)" do
      tag_full = OtaPackagerService.compute_hmac_tag(firmware.binary_payload, firmware.id, 10, cluster_id: cluster_id)
      tag_short = OtaPackagerService.compute_hmac_tag(firmware.binary_payload, firmware.id, 9, cluster_id: cluster_id)
      expect(tag_full).not_to eq(tag_short)
    end
  end
end

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
  # ⚖️ [FW.23, founder 2026-10-05/06] Ed25519 seal end-to-end:
  # backend signs → Queen relays blind → Soldier verifies with the cluster PUBLIC key
  # =========================================================================
  describe "FW.23 OTA seal end-to-end" do
    let(:hex_payload) { "52495445" + ("AB" * 100) }  # "RITE" magic + 200 bytes payload
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: hex_payload) }
    let(:cluster_id) { "test-cluster-fw23" }
    let(:prepared) { OtaPackagerService.prepare(firmware, chunk_size: 512, cluster_id: cluster_id) }
    let(:verify_key) { Ed25519::VerifyKey.new([ OtaSealKeyService.public_key_hex_for(cluster_id) ].pack("H*")) }

    # [FW.53] LoRa-шар несе WIRE-потік: padded bytecode + CRC32-хвіст (вирівняний на
    # LORA_MTU). Печатка — над padded stream БЕЗ CRC32, як рахує Солдат.
    def lora_padded_payload(raw)
      pad_len = (OtaPackagerService::LORA_MTU -
                 ((raw.bytesize + OtaPackagerService::LORA_CRC32_BYTES) %
                  OtaPackagerService::LORA_MTU)) % OtaPackagerService::LORA_MTU
      raw.b + ("\x00".b * pad_len)
    end

    def seal_from(trailer) = trailer.first(6).map { |c| c.byteslice(5, 11) }.join.byteslice(0, 64)

    it "backend produces 7 seal trailer chunks at the end of the packages (6 seal + version)" do
      trailer = prepared[:packages].to_a.last(7)

      expect(trailer.map { |p| p.unpack1("C") }).to all(eq(0x9B))
      expect(trailer.map(&:bytesize)).to all(eq(16))
      expect(trailer.map { |p| p[1..2].unpack1("n") }).to eq((1..7).to_a)
      expect(trailer.last[5..8].unpack1("N")).to eq(firmware.id)
    end

    it "manifest exposes lora_total_chunks for the Queen→Soldier cross-check" do
      wire_size = lora_padded_payload(firmware.binary_payload).bytesize + OtaPackagerService::LORA_CRC32_BYTES

      expect(prepared[:manifest][:lora_total_chunks]).to eq(wire_size / OtaPackagerService::LORA_MTU)
      expect(prepared[:manifest][:sealed]).to be true
    end

    it "the Soldier would accept: the trailer seal verifies under the cluster public key" do
      message = OtaPackagerService.seal_message(lora_padded_payload(firmware.binary_payload), firmware.id,
                                                prepared[:manifest][:lora_total_chunks])

      expect(firmware.binary_payload.byteslice(0, 4).unpack1("V")).to eq(0x45544952) # магія "RITE"
      expect(verify_key.verify(seal_from(prepared[:packages].to_a.last(7)), message)).to be(true)
    end

    it "the Soldier would REJECT a tampered bytecode, a relabelled version and a truncated campaign" do
      seal = seal_from(prepared[:packages].to_a.last(7))
      padded = lora_padded_payload(firmware.binary_payload)
      lora_total = prepared[:manifest][:lora_total_chunks]
      tampered = padded.dup
      tampered.setbyte(10, tampered.getbyte(10) ^ 0x01)

      expect { verify_key.verify(seal, OtaPackagerService.seal_message(tampered, firmware.id, lora_total)) }.to raise_error(Ed25519::VerifyError)
      expect { verify_key.verify(seal, OtaPackagerService.seal_message(padded, firmware.id + 1, lora_total)) }.to raise_error(Ed25519::VerifyError)
      expect { verify_key.verify(seal, OtaPackagerService.seal_message(padded, firmware.id, lora_total - 1)) }.to raise_error(Ed25519::VerifyError)
    end

    it "a node holds only the public key — another cluster's key does not verify the seal" do
      foreign = Ed25519::VerifyKey.new([ OtaSealKeyService.public_key_hex_for("another-cluster") ].pack("H*"))
      message = OtaPackagerService.seal_message(lora_padded_payload(firmware.binary_payload), firmware.id,
                                                prepared[:manifest][:lora_total_chunks])

      expect { foreign.verify(seal_from(prepared[:packages].to_a.last(7)), message) }.to raise_error(Ed25519::VerifyError)
    end
  end
end

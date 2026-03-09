# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OTA firmware deployment flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
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

    it "tracks firmware mismatch via TelemetryUnpackerService" do
      latest_fw = create(:bio_contract_firmware, :for_tree, :active)
      old_fw_id = latest_fw.id - 1

      service = TelemetryUnpackerService.new(nil, nil)
      service.send(:check_firmware_mismatch!, tree, old_fw_id)

      tree.reload
      expect(tree.firmware_update_status).to eq("fw_pending")
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
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaChunkable do
  describe "when included in TinyMlModel" do
    it "splits payload into 512-byte chunks by default" do
      payload = "A" * 1536
      model = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.chunks.size).to eq(3)
      expect(model.chunks.first.bytesize).to eq(512)
    end

    it "returns empty array when payload is empty" do
      model = build(:tiny_ml_model)
      allow(model).to receive(:payload_size).and_return(0)
      expect(model.chunks).to eq([])
    end

    it "returns correct total_chunks" do
      payload = "D" * 1025
      model = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.total_chunks).to eq(3)
    end

    it "accepts custom chunk_size" do
      payload = "C" * 100
      model = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.chunks(10).size).to eq(10)
    end
  end

  describe "when included in BioContractFirmware" do
    it "splits payload into 512-byte chunks by default" do
      # 3 * 512 = 1536 bytes binary = 3072 hex chars
      hex_payload = "AA" * 1536
      firmware = build(:bio_contract_firmware, bytecode_payload: hex_payload)
      expect(firmware.chunks.size).to eq(3)
      expect(firmware.chunks.first.bytesize).to eq(512)
    end

    it "returns empty array when payload is empty" do
      firmware = build(:bio_contract_firmware)
      allow(firmware).to receive(:payload_size).and_return(0)
      expect(firmware.chunks).to eq([])
    end

    it "returns correct total_chunks" do
      # 600 bytes binary = 1200 hex chars → 2 chunks (512 + 88)
      hex_payload = "BB" * 600
      firmware = build(:bio_contract_firmware, bytecode_payload: hex_payload)
      expect(firmware.total_chunks).to eq(2)
    end

    it "total_chunks matches actual chunks count" do
      hex_payload = "CC" * 2000
      firmware = build(:bio_contract_firmware, bytecode_payload: hex_payload)
      expect(firmware.total_chunks).to eq(firmware.chunks.size)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe BioContractFirmware, type: :model do
  describe "bytecode_payload validation" do
    it "accepts valid even-length HEX payload" do
      firmware = BioContractFirmware.new(version: "1.0.0", bytecode_payload: "AABBCC")
      firmware.valid?

      expect(firmware.errors[:bytecode_payload]).to be_empty
    end

    it "rejects odd-length HEX payload" do
      firmware = BioContractFirmware.new(version: "1.0.1", bytecode_payload: "ABC")
      firmware.valid?

      expect(firmware.errors[:bytecode_payload]).to be_present
    end

    it "rejects single character HEX payload" do
      firmware = BioContractFirmware.new(version: "1.0.2", bytecode_payload: "A")
      firmware.valid?

      expect(firmware.errors[:bytecode_payload]).to be_present
    end

    it "accepts two-character HEX payload (one byte)" do
      firmware = BioContractFirmware.new(version: "1.0.3", bytecode_payload: "FF")
      firmware.valid?

      expect(firmware.errors[:bytecode_payload]).to be_empty
    end
  end
end

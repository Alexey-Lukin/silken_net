# frozen_string_literal: true

require "rails_helper"

RSpec.describe BioContractFirmware, type: :model do
  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:bio_contract_firmware)).to be_valid
    end

    describe "bytecode_payload format" do
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

    describe "bytecode_payload size limit" do
      it "rejects payload exceeding 512 KB (256 KB binary)" do
        oversized = build(:bio_contract_firmware, bytecode_payload: "AA" * (256.kilobytes + 1))
        expect(oversized).not_to be_valid
        expect(oversized.errors[:bytecode_payload]).to be_present
      end

      it "accepts payload at exactly 512 KB" do
        exact = build(:bio_contract_firmware, bytecode_payload: "AA" * 256.kilobytes)
        expect(exact).to be_valid
      end
    end

    describe "target_hardware_type" do
      it "accepts 'Tree' as valid hardware type" do
        firmware = build(:bio_contract_firmware, target_hardware_type: "Tree")
        expect(firmware).to be_valid
      end

      it "accepts 'Gateway' as valid hardware type" do
        firmware = build(:bio_contract_firmware, target_hardware_type: "Gateway")
        expect(firmware).to be_valid
      end

      it "accepts nil (universal firmware)" do
        firmware = build(:bio_contract_firmware, target_hardware_type: nil)
        expect(firmware).to be_valid
      end

      it "rejects invalid hardware type" do
        firmware = build(:bio_contract_firmware, target_hardware_type: "Drone")
        expect(firmware).not_to be_valid
        expect(firmware.errors[:target_hardware_type]).to be_present
      end
    end

    describe "rollout_percentage" do
      it "accepts valid percentage (1-100)" do
        firmware = build(:bio_contract_firmware, rollout_percentage: 50)
        expect(firmware).to be_valid
      end

      it "accepts 0 as valid percentage" do
        firmware = build(:bio_contract_firmware, rollout_percentage: 0)
        expect(firmware).to be_valid
      end

      it "rejects negative percentage" do
        firmware = build(:bio_contract_firmware, rollout_percentage: -1)
        expect(firmware).not_to be_valid
      end

      it "rejects percentage over 100" do
        firmware = build(:bio_contract_firmware, rollout_percentage: 101)
        expect(firmware).not_to be_valid
      end
    end
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "optionally belongs to a tree_family" do
      family = create(:tree_family)
      firmware = create(:bio_contract_firmware, tree_family: family)
      expect(firmware.tree_family).to eq(family)
    end

    it "is valid without a tree_family" do
      firmware = build(:bio_contract_firmware, tree_family: nil)
      expect(firmware).to be_valid
    end
  end

  # =========================================================================
  # CALLBACKS (SHA-256)
  # =========================================================================
  describe "#compute_binary_sha256 (before_save)" do
    it "computes SHA-256 when payload is set" do
      firmware = create(:bio_contract_firmware, bytecode_payload: "AABBCCDD")
      binary = [ "AABBCCDD" ].pack("H*")
      expected = Digest::SHA256.hexdigest(binary)
      expect(firmware.binary_sha256).to eq(expected)
    end

    it "updates SHA-256 when payload changes" do
      firmware = create(:bio_contract_firmware, bytecode_payload: "AABB")
      firmware.update!(bytecode_payload: "CCDD")
      binary = [ "CCDD" ].pack("H*")
      expect(firmware.binary_sha256).to eq(Digest::SHA256.hexdigest(binary))
    end

    it "resets memoized binary_payload when bytecode_payload changes" do
      firmware = create(:bio_contract_firmware, bytecode_payload: "AABB")
      # Trigger memoization of old binary_payload
      _old_binary = firmware.binary_payload

      firmware.update!(bytecode_payload: "CCDD")

      # binary_payload should now reflect the NEW bytecode, not cached old value
      expect(firmware.binary_payload).to eq([ "CCDD" ].pack("H*"))
      expect(firmware.verify_integrity!).to be true
    end

    it "does not recompute SHA-256 when other attributes change" do
      firmware = create(:bio_contract_firmware)
      original_sha = firmware.binary_sha256

      firmware.update!(version: "99.9.9")

      expect(firmware.binary_sha256).to eq(original_sha)
    end
  end

  # =========================================================================
  # INTEGRITY VERIFICATION
  # =========================================================================
  describe "#verify_integrity!" do
    it "returns true when SHA-256 matches" do
      firmware = create(:bio_contract_firmware, bytecode_payload: "AABBCCDD")
      expect(firmware.verify_integrity!).to be true
    end

    it "raises IntegrityError when SHA-256 does not match" do
      firmware = create(:bio_contract_firmware, bytecode_payload: "AABBCCDD")
      firmware.update_column(:binary_sha256, "corrupted_hash_value")

      expect { firmware.verify_integrity! }.to raise_error(BioContractFirmware::IntegrityError, /SHA-256 mismatch/)
    end
  end

  # =========================================================================
  # DEPLOY GLOBALLY (Phased Rollout)
  # =========================================================================
  describe "#deploy_globally!" do
    it "sets is_active to true and records rollout_percentage" do
      firmware = create(:bio_contract_firmware)
      firmware.deploy_globally!(percentage: 5)
      firmware.reload

      expect(firmware.is_active).to be true
      expect(firmware.rollout_percentage).to eq(5)
    end

    it "defaults to 100% when percentage not specified" do
      firmware = create(:bio_contract_firmware)
      firmware.deploy_globally!
      firmware.reload

      expect(firmware.rollout_percentage).to eq(100)
    end

    it "clamps percentage to minimum 1" do
      firmware = create(:bio_contract_firmware)
      firmware.deploy_globally!(percentage: 0)
      firmware.reload

      expect(firmware.rollout_percentage).to eq(1)
    end

    it "clamps percentage to maximum 100" do
      firmware = create(:bio_contract_firmware)
      firmware.deploy_globally!(percentage: 200)
      firmware.reload

      expect(firmware.rollout_percentage).to eq(100)
    end

    it "deactivates other active firmwares" do
      old = create(:bio_contract_firmware, :active)
      new_fw = create(:bio_contract_firmware)

      new_fw.deploy_globally!(percentage: 1)

      expect(old.reload.is_active).to be false
      expect(new_fw.reload.is_active).to be true
    end
  end
end

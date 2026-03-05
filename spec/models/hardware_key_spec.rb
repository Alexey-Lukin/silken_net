# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardwareKey, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  # =========================================================================
  # NORMALIZATION
  # =========================================================================
  describe "device_uid normalization" do
    it "upcases and strips device_uid before validation" do
      key = build(:hardware_key, device_uid: "  snet-00000abc  ")
      key.valid?
      expect(key.device_uid).to eq("SNET-00000ABC")
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:hardware_key)).to be_valid
    end

    it "requires device_uid" do
      key = build(:hardware_key, device_uid: nil)
      expect(key).not_to be_valid
      expect(key.errors[:device_uid]).to be_present
    end

    it "enforces device_uid uniqueness" do
      create(:hardware_key, device_uid: "SNET-UNIQUE01")
      duplicate = build(:hardware_key, device_uid: "snet-unique01")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:device_uid]).to be_present
    end

    describe "aes_key_hex" do
      it "requires aes_key_hex" do
        expect(build(:hardware_key, aes_key_hex: nil)).not_to be_valid
      end

      it "requires exactly 64 characters" do
        short_key = "A" * 63
        expect(build(:hardware_key, aes_key_hex: short_key)).not_to be_valid
      end

      it "accepts a valid 64-character hex key" do
        valid_key = SecureRandom.hex(32).upcase
        expect(build(:hardware_key, aes_key_hex: valid_key)).to be_valid
      end

      it "rejects non-hex characters" do
        non_hex = "G" * 64
        key = build(:hardware_key, aes_key_hex: non_hex)
        expect(key).not_to be_valid
        expect(key.errors[:aes_key_hex]).to be_present
      end
    end

    describe "previous_aes_key_hex" do
      it "allows nil (no rotation has occurred yet)" do
        expect(build(:hardware_key, previous_aes_key_hex: nil)).to be_valid
      end

      it "requires exactly 64 characters when present" do
        short_key = "B" * 32
        expect(build(:hardware_key, previous_aes_key_hex: short_key)).not_to be_valid
      end

      it "accepts a valid 64-character hex previous key" do
        expect(build(:hardware_key, :with_grace_period)).to be_valid
      end
    end
  end

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================
  describe "#binary_key" do
    it "returns raw bytes unpacked from aes_key_hex" do
      key_hex = "AA" * 32
      hw_key  = build(:hardware_key, aes_key_hex: key_hex)
      expect(hw_key.binary_key).to eq([ key_hex ].pack("H*"))
    end

    it "memoizes the result (returns same object on repeated calls)" do
      hw_key = build(:hardware_key)
      first  = hw_key.binary_key
      second = hw_key.binary_key
      expect(first).to equal(second)
    end
  end

  describe "#binary_previous_key" do
    it "returns nil when previous_aes_key_hex is blank" do
      hw_key = build(:hardware_key, previous_aes_key_hex: nil)
      expect(hw_key.binary_previous_key).to be_nil
    end

    it "returns raw bytes when previous key exists" do
      prev_hex = "BB" * 32
      hw_key   = build(:hardware_key, previous_aes_key_hex: prev_hex)
      expect(hw_key.binary_previous_key).to eq([ prev_hex ].pack("H*"))
    end

    it "memoizes the result" do
      hw_key = build(:hardware_key, :with_grace_period)
      first  = hw_key.binary_previous_key
      second = hw_key.binary_previous_key
      expect(first).to equal(second)
    end
  end

  describe "#rotate_key!" do
    it "moves the current key to previous_aes_key_hex" do
      hw_key      = create(:hardware_key)
      original    = hw_key.aes_key_hex

      hw_key.rotate_key!
      hw_key.reload

      expect(hw_key.previous_aes_key_hex).to eq(original)
    end

    it "generates a new aes_key_hex" do
      hw_key   = create(:hardware_key)
      original = hw_key.aes_key_hex

      hw_key.rotate_key!
      hw_key.reload

      expect(hw_key.aes_key_hex).not_to eq(original)
      expect(hw_key.aes_key_hex.length).to eq(64)
    end

    it "records rotated_at timestamp" do
      hw_key = create(:hardware_key)

      freeze_time do
        hw_key.rotate_key!
        hw_key.reload
        expect(hw_key.rotated_at).to be_within(1.second).of(Time.current)
      end
    end

    it "resets binary_key memoization" do
      hw_key      = create(:hardware_key)
      old_binary  = hw_key.binary_key

      hw_key.rotate_key!

      expect(hw_key.binary_key).not_to eq(old_binary)
    end

    it "returns the new binary key" do
      hw_key = create(:hardware_key)
      result = hw_key.rotate_key!
      expect(result).to eq(hw_key.binary_key)
    end
  end

  describe "#clear_grace_period!" do
    it "sets previous_aes_key_hex to nil" do
      hw_key = create(:hardware_key, :with_grace_period)

      hw_key.clear_grace_period!
      hw_key.reload

      expect(hw_key.previous_aes_key_hex).to be_nil
    end

    it "resets binary_previous_key memoization" do
      hw_key = create(:hardware_key, :with_grace_period)
      hw_key.binary_previous_key # prime the memoized value

      hw_key.clear_grace_period!

      expect(hw_key.binary_previous_key).to be_nil
    end

    it "does nothing when previous key is already blank" do
      hw_key = create(:hardware_key, previous_aes_key_hex: nil)
      expect { hw_key.clear_grace_period! }.not_to raise_error
    end
  end

  describe "#owner" do
    it "returns the tree when the device_uid matches a tree's DID" do
      tree   = create(:tree)
      hw_key = create(:hardware_key, device_uid: tree.did)

      expect(hw_key.owner).to eq(tree)
    end

    it "returns the gateway when the device_uid matches a gateway's UID" do
      gateway = create(:gateway)
      hw_key  = create(:hardware_key, device_uid: gateway.uid)

      expect(hw_key.owner).to eq(gateway)
    end

    it "returns nil when no matching tree or gateway exists" do
      hw_key = create(:hardware_key, device_uid: "SNET-ORPHAN99")
      expect(hw_key.owner).to be_nil
    end
  end
end

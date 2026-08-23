# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardwareKey, type: :model do
  before do
    silence_broadcasts!(:tree_map)
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

      it "rejects lengths outside the {32, 64} hex set" do
        odd_length = "A" * 48
        expect(build(:hardware_key, aes_key_hex: odd_length)).not_to be_valid
      end

      it "accepts a 64-character hex key (Gateway CoAP AES-256, owner-less)" do
        valid_key = SecureRandom.hex(32).upcase
        expect(build(:hardware_key, aes_key_hex: valid_key)).to be_valid
      end

      it "accepts a 32-character hex key on a Tree owner (LoRa AES-128, post-ARCH.42)" do
        valid_lora_key = SecureRandom.hex(16).upcase
        expect(build(:hardware_key, :for_tree, aes_key_hex: valid_lora_key)).to be_valid
      end

      it "rejects a 64-character hex key on a Tree owner (must be AES-128 16-byte per ARCH.42)" do
        wrong_key = SecureRandom.hex(32).upcase
        record    = build(:hardware_key, :for_tree, aes_key_hex: wrong_key)
        expect(record).not_to be_valid
        expect(record.errors[:aes_key_hex].join).to include("Tree (LoRa AES-128)")
      end

      it "rejects a 32-character hex key on a Gateway owner (must be AES-256 32-byte)" do
        wrong_key = SecureRandom.hex(16).upcase
        record    = build(:hardware_key, :for_gateway, aes_key_hex: wrong_key)
        expect(record).not_to be_valid
        expect(record.errors[:aes_key_hex].join).to include("Gateway (CoAP AES-256)")
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

      it "rejects lengths outside the {32, 64} hex set" do
        short_key = "B" * 33
        expect(build(:hardware_key, previous_aes_key_hex: short_key)).not_to be_valid
      end

      it "accepts a valid hex previous key matching the active key length" do
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

    it "returns equal value bytes on repeated calls (stable output)" do
      hw_key = build(:hardware_key)
      first  = hw_key.binary_key
      second = hw_key.binary_key
      expect(first).to eq(second)
    end

    # Regression: ivar memoization (now removed) hid stale aes_key_hex updates.
    # `binary_key` recomputes per-call so attribute changes are honored
    # immediately without reload. Hot path goes through `cached_binary_key`
    # (LRU keyed by `device_uid:updated_at` — self-invalidating).
    it "reflects aes_key_hex changes without reload (no ivar memoization)" do
      hw_key  = build(:hardware_key, aes_key_hex: "AA" * 32)
      initial = hw_key.binary_key

      hw_key.aes_key_hex = "BB" * 32
      expect(hw_key.binary_key).not_to eq(initial)
      expect(hw_key.binary_key).to eq([ "BB" * 32 ].pack("H*"))
    end
  end

  describe "#cached_binary_key" do
    it "returns the same value as binary_key" do
      hw_key = build(:hardware_key)
      expect(hw_key.cached_binary_key).to eq(hw_key.binary_key)
    end

    it "caches the result in HARDWARE_KEY_CACHE with versioned key" do
      hw_key = create(:hardware_key)
      hw_key.cached_binary_key

      versioned_key = "#{hw_key.device_uid}:v:#{hw_key.updated_at.to_f}"
      expect(HARDWARE_KEY_CACHE[versioned_key]).to eq(hw_key.binary_key)
    end

    it "serves from cache on subsequent calls without hitting binary_key" do
      hw_key = create(:hardware_key)
      hw_key.cached_binary_key # prime the cache

      versioned_key = "#{hw_key.device_uid}:v:#{hw_key.updated_at.to_f}"
      expect(HARDWARE_KEY_CACHE[versioned_key]).not_to be_nil

      # Stub binary_key to verify it is NOT called again
      allow(hw_key).to receive(:binary_key)
      hw_key.cached_binary_key

      expect(hw_key).not_to have_received(:binary_key)
    end
  end

  describe "cache key versioning (race condition fix)" do
    it "uses a different cache key after update (self-invalidating)" do
      hw_key = create(:hardware_key)
      old_versioned_key = "#{hw_key.device_uid}:v:#{hw_key.updated_at.to_f}"
      hw_key.cached_binary_key # prime old cache

      expect(HARDWARE_KEY_CACHE[old_versioned_key]).to eq(hw_key.binary_key)

      hw_key.update!(aes_key_hex: SecureRandom.hex(32).upcase)
      hw_key.reload

      new_versioned_key = "#{hw_key.device_uid}:v:#{hw_key.updated_at.to_f}"
      expect(new_versioned_key).not_to eq(old_versioned_key)

      # New key returns fresh value; old cache entry is orphaned (LRU evicts later)
      new_cached = hw_key.cached_binary_key
      expect(new_cached).to eq(hw_key.binary_key)
      expect(HARDWARE_KEY_CACHE[new_versioned_key]).to eq(hw_key.binary_key)
    end

    it "returns new key after rotation without explicit cache invalidation" do
      hw_key = create(:hardware_key)
      old_cached = hw_key.cached_binary_key

      hw_key.rotate_key!
      hw_key.reload

      new_cached = hw_key.cached_binary_key
      expect(new_cached).not_to eq(old_cached)
      expect(new_cached).to eq(hw_key.binary_key)
    end

    it "does not serve stale cache after destroy and re-creation with same device_uid" do
      hw_key = create(:hardware_key)
      hw_key.cached_binary_key # prime the cache
      old_binary = hw_key.binary_key
      old_versioned_key = "#{hw_key.device_uid}:v:#{hw_key.updated_at.to_f}"

      device_uid = hw_key.device_uid
      hw_key.destroy!

      # Force a different AES key to guarantee different binary_key
      new_aes = SecureRandom.hex(32).upcase
      new_hw_key = create(:hardware_key, device_uid: device_uid, aes_key_hex: new_aes)
      new_cached = new_hw_key.cached_binary_key
      new_versioned_key = "#{new_hw_key.device_uid}:v:#{new_hw_key.updated_at.to_f}"

      # Different updated_at → different versioned key → fresh binary_key
      expect(new_versioned_key).not_to eq(old_versioned_key)
      expect(new_cached).to eq(new_hw_key.binary_key)
      expect(new_cached).not_to eq(old_binary)
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

    it "returns equal value bytes on repeated calls (stable output)" do
      hw_key = build(:hardware_key, :with_grace_period)
      first  = hw_key.binary_previous_key
      second = hw_key.binary_previous_key
      expect(first).to eq(second)
    end
  end

  # [SEC.11] Lorenz K_seed lifecycle is parallel to the AES key:
  # encrypted at rest, optional during the field-migration window,
  # and exposed as raw bytes for SilkenNet::SeedDerivation consumers.
  describe "#binary_lorenz_seed" do
    it "returns nil when lorenz_seed_hex is blank" do
      hw_key = build(:hardware_key, lorenz_seed_hex: nil)
      expect(hw_key.binary_lorenz_seed).to be_nil
    end

    it "returns raw 32 bytes when seed is present" do
      seed_hex = "AB" * 32
      hw_key   = build(:hardware_key, lorenz_seed_hex: seed_hex)
      expect(hw_key.binary_lorenz_seed.bytesize).to eq(32)
      expect(hw_key.binary_lorenz_seed).to eq([ seed_hex ].pack("H*"))
    end

    it "returns equal 32 bytes on repeated calls (stable output)" do
      hw_key = build(:hardware_key, lorenz_seed_hex: "CD" * 32)
      first  = hw_key.binary_lorenz_seed
      second = hw_key.binary_lorenz_seed
      expect(first).to eq(second)
    end

    it "validates lorenz_seed_hex length and HEX format when provided" do
      expect(build(:hardware_key, lorenz_seed_hex: "AB" * 31)).not_to be_valid
      expect(build(:hardware_key, lorenz_seed_hex: ("XY" * 32))).not_to be_valid
      expect(build(:hardware_key, lorenz_seed_hex: ("AB" * 32))).to be_valid
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

    it "generates a new aes_key_hex of the same length (Gateway-shaped default = 64 hex)" do
      hw_key   = create(:hardware_key)
      original = hw_key.aes_key_hex

      hw_key.rotate_key!
      hw_key.reload

      expect(hw_key.aes_key_hex).not_to eq(original)
      expect(hw_key.aes_key_hex.length).to eq(original.length)
      expect(hw_key.aes_key_hex.length).to eq(64) # Gateway shape (AES-256 CoAP)
    end

    it "rotates a Tree (AES-128 LoRa) key into another 32-hex key (post-ARCH.42)" do
      hw_key   = create(:hardware_key, :for_tree)
      original = hw_key.aes_key_hex
      expect(original.length).to eq(32)

      hw_key.rotate_key!
      hw_key.reload

      expect(hw_key.aes_key_hex).not_to eq(original)
      expect(hw_key.aes_key_hex.length).to eq(32)
      expect(hw_key.previous_aes_key_hex).to eq(original)
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
      # Post-ARCH.42: Tree-shaped HardwareKey має 32 hex (AES-128 LoRa).
      hw_key = create(:hardware_key, device_uid: tree.did, aes_key_hex: SecureRandom.hex(16).upcase)

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

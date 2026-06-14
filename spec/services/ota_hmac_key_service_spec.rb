# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaHmacKeyService do
  describe ".fetch_for" do
    context "with PROVISIONING_MASTER_KEY (HKDF mode)" do
      it "derives deterministic key from cluster_id via HKDF-SHA256" do
        key1 = described_class.fetch_for("cluster-A")
        key2 = described_class.fetch_for("cluster-A")
        expect(key1).to eq(key2)
      end

      it "returns 64-character hex string (32 bytes / AES-256 size)" do
        key = described_class.fetch_for("cluster-A")
        expect(key).to match(/\A[0-9A-F]{64}\z/)
      end

      it "produces different keys for different cluster_ids" do
        key_a = described_class.fetch_for("cluster-A")
        key_b = described_class.fetch_for("cluster-B")
        expect(key_a).not_to eq(key_b)
      end

      it "uses domain-separated info '#{described_class::HKDF_INFO}'" do
        # Ensure constant matches design spec (docs/03_06 §4).
        expect(described_class::HKDF_INFO).to eq("silken-ota-hmac-v1")
      end

      it "differs from HardwareKeyService AES key for the same input" do
        # Domain separation: same master_key + same input string MUST NOT
        # produce the same K_ota and K_aes_device (different `info` field).
        cluster_id = "shared-id-1"
        ota_key    = described_class.fetch_for(cluster_id)
        device_key = HardwareKeyService.derive_device_key(cluster_id)
        expect(ota_key).not_to eq(device_key)
      end

      it "raises ArgumentError when cluster_id is blank" do
        expect { described_class.fetch_for("") }.to raise_error(ArgumentError, /cluster_id/)
        expect { described_class.fetch_for(nil) }.to raise_error(ArgumentError, /cluster_id/)
      end
    end

    context "without PROVISIONING_MASTER_KEY [SEC.11 hard cutover]" do
      around do |example|
        original = ENV["PROVISIONING_MASTER_KEY"]
        ENV["PROVISIONING_MASTER_KEY"] = nil
        example.run
        ENV["PROVISIONING_MASTER_KEY"] = original
      end

      it "raises SecurityError — no SecureRandom fallback" do
        expect {
          described_class.fetch_for("cluster-A")
        }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
      end
    end
  end

  describe ".fetch_binary_for" do
    it "returns 32-byte binary string" do
      bin = described_class.fetch_binary_for("cluster-A")
      expect(bin.bytesize).to eq(32)
      expect(bin.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "is hex-equivalent to fetch_for" do
      hex = described_class.fetch_for("cluster-A")
      bin = described_class.fetch_binary_for("cluster-A")
      expect(bin.unpack1("H*").upcase).to eq(hex)
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.23, ⚖️ founder 2026-10-05/06] Ed25519-ключ печатки OTA-контракту кластера.
RSpec.describe OtaSealKeyService do
  describe ".signing_key_for" do
    it "derives a deterministic Ed25519 key per cluster from the master key" do
      key_a = described_class.signing_key_for("cluster-A").to_bytes

      expect(described_class.signing_key_for("cluster-A").to_bytes).to eq(key_a)
      expect(described_class.signing_key_for("cluster-B").to_bytes).not_to eq(key_a)
    end

    # Незалежний оракул: seed — це HKDF саме з цими параметрами, а не будь-які 32 байти.
    it "seeds Ed25519 with HKDF(master, \"cluster:<id>\", \"silken-ota-ed25519-v1\")" do
      master = "di-alive-proof-master-key-distinct"
      seed = OpenSSL::KDF.hkdf(master, salt: "cluster:cluster-A", info: "silken-ota-ed25519-v1",
                                       length: 32, hash: "SHA256")

      expect(described_class.signing_key_for("cluster-A", master_key: master).to_bytes).to eq(seed)
    end

    it "raises ArgumentError when cluster_id is blank" do
      expect { described_class.signing_key_for("") }.to raise_error(ArgumentError, /cluster_id/)
      expect { described_class.signing_key_for(nil) }.to raise_error(ArgumentError, /cluster_id/)
    end

    context "without PROVISIONING_MASTER_KEY [SEC.11 hard cutover]" do
      around do |example|
        original = ENV["PROVISIONING_MASTER_KEY"]
        ENV["PROVISIONING_MASTER_KEY"] = nil
        example.run
        ENV["PROVISIONING_MASTER_KEY"] = original
      end

      it "raises SecurityError — no random fallback" do
        expect { described_class.signing_key_for("cluster-A") }.to raise_error(SecurityError, /PROVISIONING_MASTER_KEY/)
      end
    end
  end

  describe ".public_key_hex_for" do
    it "returns the 32-byte verify key as 64 upper-case hex — what the factory writes into KPUB" do
      hex = described_class.public_key_hex_for("cluster-A")

      expect(hex).to match(/\A[0-9A-F]{64}\z/)
      expect(hex).to eq(described_class.signing_key_for("cluster-A").verify_key.to_bytes.unpack1("H*").upcase)
    end

    it "verifies a seal made by the same cluster key and rejects another cluster's" do
      message = "RITE\x03\x00\x00\x00".b
      seal = described_class.signing_key_for("cluster-A").sign(message)
      own = Ed25519::VerifyKey.new([ described_class.public_key_hex_for("cluster-A") ].pack("H*"))
      foreign = Ed25519::VerifyKey.new([ described_class.public_key_hex_for("cluster-B") ].pack("H*"))

      expect(own.verify(seal, message)).to be(true)
      expect { foreign.verify(seal, message) }.to raise_error(Ed25519::VerifyError)
    end
  end
end

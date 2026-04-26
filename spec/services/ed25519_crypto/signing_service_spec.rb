# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ed25519Crypto::SigningService do
  describe ".generate_keypair" do
    it "returns a hash with seed_hex and public_key_hex" do
      keypair = described_class.generate_keypair

      expect(keypair).to have_key(:seed_hex)
      expect(keypair).to have_key(:public_key_hex)
    end

    it "generates 32-byte seed (64 hex chars)" do
      keypair = described_class.generate_keypair

      expect(keypair[:seed_hex]).to match(/\A[0-9a-f]{64}\z/)
    end

    it "generates 32-byte public key (64 hex chars)" do
      keypair = described_class.generate_keypair

      expect(keypair[:public_key_hex]).to match(/\A[0-9a-f]{64}\z/)
    end

    it "generates unique keypairs on each call" do
      keypair1 = described_class.generate_keypair
      keypair2 = described_class.generate_keypair

      expect(keypair1[:seed_hex]).not_to eq(keypair2[:seed_hex])
    end
  end

  describe ".public_key_from_seed" do
    it "derives the correct public key from seed" do
      keypair = described_class.generate_keypair

      derived_pubkey = described_class.public_key_from_seed(keypair[:seed_hex])

      expect(derived_pubkey).to eq(keypair[:public_key_hex])
    end

    it "raises SigningError for nil seed" do
      expect {
        described_class.public_key_from_seed(nil)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /seed is required/)
    end

    it "raises SigningError for empty seed" do
      expect {
        described_class.public_key_from_seed("")
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /seed is required/)
    end

    it "raises SigningError for invalid hex" do
      expect {
        described_class.public_key_from_seed("zzzz" * 16)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /must be a valid hex string/)
    end

    it "raises SigningError for wrong length" do
      expect {
        described_class.public_key_from_seed("abcd")
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /must be exactly 32 bytes/)
    end
  end

  describe ".sign" do
    let(:keypair) { described_class.generate_keypair }

    it "returns a 64-byte signature (128 hex chars)" do
      signature = described_class.sign(keypair[:seed_hex], "test message")

      expect(signature).to match(/\A[0-9a-f]{128}\z/)
    end

    it "produces deterministic signatures for the same key and message" do
      sig1 = described_class.sign(keypair[:seed_hex], "same message")
      sig2 = described_class.sign(keypair[:seed_hex], "same message")

      expect(sig1).to eq(sig2)
    end

    it "produces different signatures for different messages" do
      sig1 = described_class.sign(keypair[:seed_hex], "message A")
      sig2 = described_class.sign(keypair[:seed_hex], "message B")

      expect(sig1).not_to eq(sig2)
    end

    it "raises SigningError for nil seed" do
      expect {
        described_class.sign(nil, "message")
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /seed is required/)
    end

    it "handles binary message data" do
      binary_data = "\x00\x01\xFF\xFE" * 8
      signature = described_class.sign(keypair[:seed_hex], binary_data)

      expect(signature).to match(/\A[0-9a-f]{128}\z/)
    end
  end

  describe ".verify" do
    let(:keypair) { described_class.generate_keypair }
    let(:message) { "verify this message" }
    let(:signature) { described_class.sign(keypair[:seed_hex], message) }

    it "returns true for valid signature" do
      result = described_class.verify(keypair[:public_key_hex], signature, message)

      expect(result).to be true
    end

    it "returns false for tampered message" do
      result = described_class.verify(keypair[:public_key_hex], signature, "tampered message")

      expect(result).to be false
    end

    it "returns false for wrong public key" do
      other_keypair = described_class.generate_keypair

      result = described_class.verify(other_keypair[:public_key_hex], signature, message)

      expect(result).to be false
    end

    it "returns false for corrupted signature" do
      corrupted = "00" * 64

      result = described_class.verify(keypair[:public_key_hex], corrupted, message)

      expect(result).to be false
    end

    it "raises SigningError for nil public_key" do
      expect {
        described_class.verify(nil, signature, message)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /public_key is required/)
    end

    it "raises SigningError for nil signature" do
      expect {
        described_class.verify(keypair[:public_key_hex], nil, message)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /signature is required/)
    end
  end

  describe "full sign-verify cycle" do
    it "signs and verifies Solana-style transaction payload" do
      keypair = described_class.generate_keypair
      payload = JSON.generate({
        type: "spl_token_transfer",
        recipient: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV",
        amount: 10_000
      })

      signature = described_class.sign(keypair[:seed_hex], payload)
      result = described_class.verify(keypair[:public_key_hex], signature, payload)

      expect(result).to be true
    end

    it "signs and verifies peaq DID document" do
      keypair = described_class.generate_keypair
      did_string = "did:peaq:0x#{"a" * 40}"

      signature = described_class.sign(keypair[:seed_hex], did_string)
      result = described_class.verify(keypair[:public_key_hex], signature, did_string)

      expect(result).to be true
    end

    it "signs and verifies empty message" do
      keypair = described_class.generate_keypair
      signature = described_class.sign(keypair[:seed_hex], "")
      result = described_class.verify(keypair[:public_key_hex], signature, "")

      expect(result).to be true
    end

    it "signs and verifies very large message (1MB)" do
      keypair = described_class.generate_keypair
      large_message = "A" * (1024 * 1024)

      signature = described_class.sign(keypair[:seed_hex], large_message)
      result = described_class.verify(keypair[:public_key_hex], signature, large_message)

      expect(result).to be true
    end
  end

  describe "validate_hex! edge cases" do
    it "raises for seed with 63 hex chars (1 char short)" do
      expect {
        described_class.public_key_from_seed("a" * 63)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /must be exactly 32 bytes/)
    end

    it "raises for seed with 65 hex chars (1 char over)" do
      expect {
        described_class.public_key_from_seed("a" * 65)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /must be exactly 32 bytes/)
    end

    it "accepts uppercase hex in seed" do
      keypair = described_class.generate_keypair
      uppercase_seed = keypair[:seed_hex].upcase

      # Should not raise
      pubkey = described_class.public_key_from_seed(uppercase_seed)
      expect(pubkey).to match(/\A[0-9a-f]{64}\z/)
    end

    it "raises for hex string with spaces" do
      expect {
        described_class.public_key_from_seed("ab cd " * 11)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError)
    end

    it "raises for hex string with 0x prefix" do
      expect {
        described_class.public_key_from_seed("0x" + "a" * 62)
      }.to raise_error(Ed25519Crypto::SigningService::SigningError, /must be a valid hex string/)
    end
  end

  describe ".sign edge cases" do
    let(:keypair) { described_class.generate_keypair }

    it "handles nil message (converts to empty string via .to_s)" do
      # nil.to_s = ""
      sig1 = described_class.sign(keypair[:seed_hex], nil)
      sig2 = described_class.sign(keypair[:seed_hex], "")

      expect(sig1).to eq(sig2)
    end

    it "handles integer message (converts via .to_s)" do
      sig = described_class.sign(keypair[:seed_hex], 42)
      expect(sig).to match(/\A[0-9a-f]{128}\z/)

      # Verify with string equivalent
      result = described_class.verify(keypair[:public_key_hex], sig, "42")
      expect(result).to be true
    end
  end

  describe ".verify edge cases" do
    let(:keypair) { described_class.generate_keypair }

    it "returns false for correct-length but wrong-bytes public key" do
      wrong_pubkey = "0" * 64
      signature = described_class.sign(keypair[:seed_hex], "test")

      result = described_class.verify(wrong_pubkey, signature, "test")
      expect(result).to be false
    end

    it "returns false when message has trailing whitespace" do
      signature = described_class.sign(keypair[:seed_hex], "test")
      result = described_class.verify(keypair[:public_key_hex], signature, "test ")

      expect(result).to be false
    end

    it "returns false when message is truncated" do
      signature = described_class.sign(keypair[:seed_hex], "test message")
      result = described_class.verify(keypair[:public_key_hex], signature, "test")

      expect(result).to be false
    end
  end
end

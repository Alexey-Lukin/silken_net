# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cryptography::LoraCcm, type: :service do
  let(:zero_key)      { ("\x00".b * 16).b }
  let(:did_bytes)     { "\x01\x02\x03\x04".b }
  let(:frame_counter) { 5 }
  let(:plaintext)     { "\x01\x02\x03\x04\x05\x06\x07\x08".b }

  # Golden vector — produced by OpenSSL aes-128-ccm with:
  #   key   = 00 × 16
  #   nonce = DID(01020304) || FC(00000005) || 00 × 4
  #   aad   = DID || FC (8 bytes)
  #   pt    = 01 02 03 04 05 06 07 08
  # If OpenSSL ever changes its CCM internals, this guards the contract
  # the firmware HAL_CRYPEx_AESCCM_Encrypt is expected to match bit-for-bit.
  let(:expected_ciphertext) { [ "08ceca97bbf4fdc5" ].pack("H*") }
  let(:expected_mic)        { [ "a6d8e20ce0deeae9" ].pack("H*") }

  describe ".encrypt" do
    it "produces the documented golden ciphertext and 8-byte MIC" do
      ct, mic = described_class.encrypt(
        key: zero_key,
        did_bytes: did_bytes,
        frame_counter: frame_counter,
        plaintext: plaintext
      )

      expect(ct).to eq(expected_ciphertext)
      expect(mic).to eq(expected_mic)
      expect(mic.bytesize).to eq(8)
    end

    it "produces different ciphertexts for different frame counters" do
      ct1, mic1 = described_class.encrypt(key: zero_key, did_bytes: did_bytes,
                                          frame_counter: 1, plaintext: plaintext)
      ct2, mic2 = described_class.encrypt(key: zero_key, did_bytes: did_bytes,
                                          frame_counter: 2, plaintext: plaintext)

      expect(ct1).not_to eq(ct2)
      expect(mic1).not_to eq(mic2)
    end
  end

  describe ".decrypt" do
    it "round-trips encrypt → decrypt for the golden vector" do
      pt = described_class.decrypt(
        key: zero_key,
        did_bytes: did_bytes,
        frame_counter: frame_counter,
        ciphertext: expected_ciphertext,
        mic: expected_mic
      )
      expect(pt).to eq(plaintext)
      expect(pt.bytesize).to eq(8)
    end

    it "raises AuthError when the MIC is tampered" do
      bad_mic = expected_mic.dup
      bad_mic.setbyte(0, bad_mic.getbyte(0) ^ 0x01)

      expect {
        described_class.decrypt(
          key: zero_key,
          did_bytes: did_bytes,
          frame_counter: frame_counter,
          ciphertext: expected_ciphertext,
          mic: bad_mic
        )
      }.to raise_error(Cryptography::LoraCcm::AuthError, /CCM authentication failed/)
    end

    it "raises AuthError when the ciphertext is tampered" do
      bad_ct = expected_ciphertext.dup
      bad_ct.setbyte(3, bad_ct.getbyte(3) ^ 0x55)

      expect {
        described_class.decrypt(
          key: zero_key,
          did_bytes: did_bytes,
          frame_counter: frame_counter,
          ciphertext: bad_ct,
          mic: expected_mic
        )
      }.to raise_error(Cryptography::LoraCcm::AuthError)
    end

    it "raises AuthError when DID is wrong (AAD mismatch)" do
      expect {
        described_class.decrypt(
          key: zero_key,
          did_bytes: "\xFF\xFF\xFF\xFF".b,
          frame_counter: frame_counter,
          ciphertext: expected_ciphertext,
          mic: expected_mic
        )
      }.to raise_error(Cryptography::LoraCcm::AuthError)
    end

    it "raises AuthError when the frame counter is wrong (AAD + nonce mismatch)" do
      expect {
        described_class.decrypt(
          key: zero_key,
          did_bytes: did_bytes,
          frame_counter: 999,
          ciphertext: expected_ciphertext,
          mic: expected_mic
        )
      }.to raise_error(Cryptography::LoraCcm::AuthError)
    end

    it "raises AuthError when the key is wrong" do
      expect {
        described_class.decrypt(
          key: ("\xFF".b * 16),
          did_bytes: did_bytes,
          frame_counter: frame_counter,
          ciphertext: expected_ciphertext,
          mic: expected_mic
        )
      }.to raise_error(Cryptography::LoraCcm::AuthError)
    end
  end

  describe "input validation" do
    it "rejects a key that is not 16 bytes (AES-128 only)" do
      expect {
        described_class.encrypt(key: "\x00".b * 32, did_bytes: did_bytes,
                                frame_counter: 1, plaintext: plaintext)
      }.to raise_error(Cryptography::LoraCcm::InputError, /key must be 16 bytes/)
    end

    it "rejects a DID that is not 4 bytes" do
      expect {
        described_class.encrypt(key: zero_key, did_bytes: "\x01\x02",
                                frame_counter: 1, plaintext: plaintext)
      }.to raise_error(Cryptography::LoraCcm::InputError, /did_bytes must be 4 bytes/)
    end

    it "rejects a frame counter outside uint32 range" do
      expect {
        described_class.encrypt(key: zero_key, did_bytes: did_bytes,
                                frame_counter: -1, plaintext: plaintext)
      }.to raise_error(Cryptography::LoraCcm::InputError, /uint32/)

      expect {
        described_class.encrypt(key: zero_key, did_bytes: did_bytes,
                                frame_counter: 2**32, plaintext: plaintext)
      }.to raise_error(Cryptography::LoraCcm::InputError, /uint32/)
    end

    it "rejects a payload that is not 8 bytes" do
      expect {
        described_class.encrypt(key: zero_key, did_bytes: did_bytes,
                                frame_counter: 1, plaintext: "\x00".b * 4)
      }.to raise_error(Cryptography::LoraCcm::InputError, /payload must be 8 bytes/)
    end

    it "rejects a MIC that is not 8 bytes during decrypt" do
      expect {
        described_class.decrypt(key: zero_key, did_bytes: did_bytes,
                                frame_counter: 1, ciphertext: expected_ciphertext,
                                mic: "\x00".b * 4)
      }.to raise_error(Cryptography::LoraCcm::InputError, /mic must be 8 bytes/)
    end
  end

  describe ".build_nonce" do
    it "produces a 12-byte nonce matching DID || FC || 4 zero bytes" do
      nonce = described_class.build_nonce(did_bytes, frame_counter)
      expect(nonce.bytesize).to eq(12)
      expect(nonce.byteslice(0, 4)).to eq(did_bytes)
      expect(nonce.byteslice(4, 4)).to eq([ frame_counter ].pack("N"))
      expect(nonce.byteslice(8, 4)).to eq("\x00\x00\x00\x00".b)
    end
  end

  describe ".build_aad" do
    it "produces an 8-byte AAD = DID || FrameCounter (BE)" do
      aad = described_class.build_aad(did_bytes, 0xDEADBEEF)
      expect(aad).to eq(did_bytes + [ 0xDEADBEEF ].pack("N"))
      expect(aad.bytesize).to eq(Cryptography::LoraCcm::AAD_LEN)
    end
  end
end

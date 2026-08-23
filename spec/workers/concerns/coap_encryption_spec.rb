# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoapEncryption do
  # Тестовий воркер для перевірки CoapEncryption concern
  let(:test_worker_class) do
    Class.new do
      include Sidekiq::Job
      include CoapEncryption

      def perform(payload, key)
        coap_encrypt(payload, key)
      end

      # Expose private wrap helper for whitebox tests of the FW.20 envelope
      def public_wrap(payload, ts = nil)
        wrap_with_time_sync(payload, ts)
      end
    end
  end

  let(:worker) { test_worker_class.new }
  let(:key) { OpenSSL::Random.random_bytes(32) } # AES-256 key

  # [FW.20] Helper: decrypt CBC ciphertext and return the raw plaintext
  # (CMD_TIME_SYNC envelope still attached, padding null-bytes intact).
  def decrypt(encrypted, encryption_key = key)
    iv = encrypted.byteslice(0, 16)
    ct = encrypted.byteslice(16..)

    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.decrypt
    cipher.key = encryption_key
    cipher.iv = iv
    cipher.padding = 0
    cipher.update(ct) + cipher.final
  end

  describe "#coap_encrypt" do
    # [FW.20] Plaintext layout reminder:
    #   [0x9C marker][ts_be:4][user_payload:N][zero-padding to next 16-byte boundary]
    # So ciphertext_len(plaintext_len) = ceil((5 + plaintext_len) / 16) * 16.
    it "returns data starting with a 16-byte IV" do
      result = worker.coap_encrypt("hello", key)
      expect(result.bytesize).to be >= 16
    end

    it "produces output aligned to 16-byte AES blocks" do
      result = worker.coap_encrypt("test payload", key)
      ciphertext_size = result.bytesize - 16
      expect(ciphertext_size % 16).to eq(0)
    end

    it "produces different output for the same input (random IV)" do
      encrypted1 = worker.coap_encrypt("same data", key)
      encrypted2 = worker.coap_encrypt("same data", key)
      expect(encrypted1).not_to eq(encrypted2)
    end

    it "encrypts data that can be decrypted with the same key (envelope + payload survive)" do
      original = "CMD:OPEN_VALVE:3600:42:abc-123"
      encrypted = worker.coap_encrypt(original, key)

      decrypted = decrypt(encrypted)
      # Strip [marker:1][ts:4] envelope, then trim null padding
      inner = decrypted.byteslice(5..).delete("\x00")
      expect(inner).to eq(original)
    end

    it "handles empty payload (envelope alone occupies 5 bytes → 1 ciphertext block)" do
      result = worker.coap_encrypt("", key)
      # Envelope = 5 bytes → padded to 16 → IV(16) + ciphertext(16) = 32
      expect(result.bytesize).to eq(32)
    end

    it "handles payload that is exact multiple of block size" do
      payload = "A" * 16
      result = worker.coap_encrypt(payload, key)
      # 5 + 16 = 21 → padded to 32 → IV(16) + ct(32) = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 1-byte payload with correct padding" do
      result = worker.coap_encrypt("X", key)
      # 5 + 1 = 6 → padded to 16 → IV(16) + ct(16) = 32
      expect(result.bytesize).to eq(32)
    end

    it "handles 11-byte payload (envelope+payload exactly = 16 → no padding)" do
      result = worker.coap_encrypt("A" * 11, key)
      # 5 + 11 = 16 → 0 padding → IV(16) + ct(16) = 32
      expect(result.bytesize).to eq(32)
    end

    it "handles 12-byte payload (1 byte over block boundary)" do
      result = worker.coap_encrypt("A" * 12, key)
      # 5 + 12 = 17 → padded to 32 → IV(16) + ct(32) = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 27-byte payload (envelope+payload = 32 exact)" do
      result = worker.coap_encrypt("D" * 27, key)
      # 5 + 27 = 32 → 0 padding → IV(16) + ct(32) = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 28-byte payload (1 byte over 2 blocks)" do
      result = worker.coap_encrypt("E" * 28, key)
      # 5 + 28 = 33 → padded to 48 → IV(16) + ct(48) = 64
      expect(result.bytesize).to eq(64)
    end

    it "correctly handles binary payload with null bytes" do
      binary_payload = "\x00\x01\x02\xFF\xFE\xFD".b
      encrypted = worker.coap_encrypt(binary_payload, key)
      decrypted = decrypt(encrypted)

      inner = decrypted.byteslice(5, binary_payload.bytesize)
      expect(inner).to eq(binary_payload)
    end

    it "pads with only null bytes (firmware-compatible)" do
      payload = "HELLO"
      encrypted = worker.coap_encrypt(payload, key)
      decrypted = decrypt(encrypted)

      # Plaintext = [5 envelope][5 payload][6 null padding] inside a 16-byte block
      padding = decrypted.byteslice((5 + payload.bytesize)..)
      expect(padding.bytes).to all(eq(0))
    end

    it "generates different IV for each encryption" do
      ivs = 10.times.map do
        encrypted = worker.coap_encrypt("test", key)
        encrypted.byteslice(0, 16)
      end

      expect(ivs.uniq.size).to eq(10)
    end
  end

  describe "[FW.20] CMD_TIME_SYNC envelope" do
    it "exposes the 0x9C marker constant" do
      expect(CoapEncryption::CMD_TIME_SYNC).to eq(0x9C)
      expect(CoapEncryption::TIME_SYNC_HEADER_SIZE).to eq(5)
    end

    it "wraps payload as [0x9C][ts_be_u32][payload]" do
      wrapped = worker.public_wrap("CMD:OPEN_VALVE:3600:42:abc", 1_700_000_000)
      expect(wrapped.bytes.first).to eq(0x9C)
      expect(wrapped.byteslice(1, 4).unpack1("N")).to eq(1_700_000_000)
      expect(wrapped.byteslice(5..)).to eq("CMD:OPEN_VALVE:3600:42:abc")
    end

    it "uses Time.now.utc.to_i when no explicit timestamp is provided" do
      before = Time.now.utc.to_i
      wrapped = worker.public_wrap("payload")
      after = Time.now.utc.to_i
      ts = wrapped.byteslice(1, 4).unpack1("N")
      expect(ts).to be_between(before, after)
    end

    it "[round-trip] decrypt yields recoverable [marker][ts][payload] structure" do
      encrypted = worker.coap_encrypt("CMD:CLOSE", key, timestamp: 1_762_000_000)
      decrypted = decrypt(encrypted)

      expect(decrypted.bytes.first).to eq(0x9C)
      expect(decrypted.byteslice(1, 4).unpack1("N")).to eq(1_762_000_000)
      inner_with_padding = decrypted.byteslice(5..)
      expect(inner_with_padding.byteslice(0, 9)).to eq("CMD:CLOSE")
    end

    it "envelope timestamp progresses monotonically across successive encryptions" do
      timestamps = 5.times.map do
        sleep 0.001 # ensure distinct microseconds; only second-level matters
        encrypted = worker.coap_encrypt("ping", key)
        decrypt(encrypted).byteslice(1, 4).unpack1("N")
      end
      # Allow equal consecutive (sub-second) but never going backwards
      timestamps.each_cons(2) { |a, b| expect(b).to be >= a }
    end

    it "different inner payloads share the same envelope structure (marker first byte)" do
      [ "X".b, "CMD:OPEN".b, "\x99\x00\x01\x00\x05".b + ("\xAB".b * 11) ].each do |payload|
        decrypted = decrypt(worker.coap_encrypt(payload, key))
        expect(decrypted.bytes.first).to eq(0x9C),
          "Expected 0x9C envelope marker for payload #{payload.inspect}"
      end
    end

    it "32-bit timestamp wrap is acceptable (year-2106 rollover)" do
      huge_ts = 2**32 + 42 # overflows uint32
      wrapped = worker.public_wrap("payload", huge_ts)
      # Wraps via & 0xFFFFFFFF — stored value is 42
      expect(wrapped.byteslice(1, 4).unpack1("N")).to eq(42)
    end
  end
end

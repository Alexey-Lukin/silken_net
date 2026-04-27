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
    end
  end

  let(:worker) { test_worker_class.new }
  let(:key) { OpenSSL::Random.random_bytes(32) } # AES-256 key

  describe "#coap_encrypt" do
    it "returns data starting with a 16-byte IV" do
      result = worker.coap_encrypt("hello", key)
      expect(result.bytesize).to be >= 16
    end

    it "produces output aligned to 16-byte AES blocks" do
      result = worker.coap_encrypt("test payload", key)
      # Output = IV(16) + ciphertext(N*16)
      ciphertext_size = result.bytesize - 16
      expect(ciphertext_size % 16).to eq(0)
    end

    it "produces different output for the same input (random IV)" do
      encrypted1 = worker.coap_encrypt("same data", key)
      encrypted2 = worker.coap_encrypt("same data", key)
      expect(encrypted1).not_to eq(encrypted2)
    end

    it "encrypts data that can be decrypted with the same key" do
      original = "CMD:OPEN_VALVE:3600:42:abc-123"
      encrypted = worker.coap_encrypt(original, key)

      # Decrypt
      iv = encrypted.byteslice(0, 16)
      ciphertext = encrypted.byteslice(16..)

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0

      decrypted = cipher.update(ciphertext) + cipher.final
      # Remove null padding
      decrypted = decrypted.delete("\x00")
      expect(decrypted).to eq(original)
    end

    it "handles empty payload" do
      result = worker.coap_encrypt("", key)
      # Empty payload: padding_length = (16 - 0) % 16 = 0, so no ciphertext block is produced
      expect(result.bytesize).to eq(16) # IV only
    end

    it "handles payload that is exact multiple of block size" do
      payload = "A" * 16 # Exactly 1 AES block
      result = worker.coap_encrypt(payload, key)
      expect(result.bytesize).to eq(32) # 16 IV + 16 ciphertext
    end

    it "handles 1-byte payload with correct padding" do
      result = worker.coap_encrypt("X", key)
      # 1 byte + 15 bytes padding = 16 bytes ciphertext + 16 IV = 32
      expect(result.bytesize).to eq(32)
    end

    it "handles 15-byte payload (1 byte short of block)" do
      result = worker.coap_encrypt("A" * 15, key)
      # 15 bytes + 1 byte padding = 16 bytes ciphertext + 16 IV = 32
      expect(result.bytesize).to eq(32)
    end

    it "handles 17-byte payload (1 byte over block)" do
      result = worker.coap_encrypt("B" * 17, key)
      # 17 bytes + 15 bytes padding = 32 bytes ciphertext + 16 IV = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 31-byte payload (1 byte short of 2 blocks)" do
      result = worker.coap_encrypt("C" * 31, key)
      # 31 bytes + 1 byte padding = 32 bytes ciphertext + 16 IV = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 32-byte payload (exact 2 blocks)" do
      result = worker.coap_encrypt("D" * 32, key)
      # 32 bytes + 0 padding = 32 bytes ciphertext + 16 IV = 48
      expect(result.bytesize).to eq(48)
    end

    it "handles 33-byte payload (1 byte over 2 blocks)" do
      result = worker.coap_encrypt("E" * 33, key)
      # 33 bytes + 15 padding = 48 bytes ciphertext + 16 IV = 64
      expect(result.bytesize).to eq(64)
    end

    it "correctly handles binary payload with null bytes" do
      binary_payload = "\x00\x01\x02\xFF\xFE\xFD"
      encrypted = worker.coap_encrypt(binary_payload, key)

      # Decrypt and verify
      iv = encrypted.byteslice(0, 16)
      ciphertext = encrypted.byteslice(16..)

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0

      decrypted = cipher.update(ciphertext) + cipher.final
      # Binary payload with null bytes — compare raw bytes (force same encoding)
      expect(decrypted.byteslice(0, binary_payload.bytesize)).to eq(binary_payload.b)
    end

    it "pads with only null bytes (firmware-compatible)" do
      payload = "HELLO"
      encrypted = worker.coap_encrypt(payload, key)

      iv = encrypted.byteslice(0, 16)
      ciphertext = encrypted.byteslice(16..)

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.padding = 0

      decrypted = cipher.update(ciphertext) + cipher.final
      padding = decrypted.byteslice(payload.bytesize..)
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
end

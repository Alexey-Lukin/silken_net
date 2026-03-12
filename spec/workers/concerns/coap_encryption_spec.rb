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
  end
end

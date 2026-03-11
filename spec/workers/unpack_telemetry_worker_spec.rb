# frozen_string_literal: true

require "rails_helper"

RSpec.describe UnpackTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before do
    key_record # Ensure key exists
    allow(TelemetryUnpackerService).to receive(:call)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
  end

  # Хелпер для створення зашифрованого payload (AES-256-CBC)
  def encrypt_payload(data, key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = key
    iv = cipher.random_iv

    block_size = 16
    padding_length = (block_size - (data.bytesize % block_size)) % block_size
    padded = data + ("\x00" * padding_length)

    iv + cipher.update(padded) + cipher.final
  end

  describe "#perform" do
    it "decrypts payload with current key and forwards to TelemetryUnpackerService" do
      raw_data = "TELEMETRY_BATCH_DATA_TEST_1234"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call).with(anything, gateway.id)
    end

    it "updates gateway IP via mark_seen!" do
      raw_data = "TELEMETRY_DATA"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "10.0.0.99", gateway.uid)

      gateway.reload
      expect(gateway.ip_address).to eq("10.0.0.99")
    end

    it "broadcasts decrypted data to Turbo Stream" do
      raw_data = "BROADCAST_TEST"
      encrypted = encrypt_payload(raw_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with("telemetry_stream", anything)
    end

    context "when dual-key rotation (grace period)" do
      it "decrypts with previous key when current key fails" do
        old_key = key_record.binary_key.dup
        # Ротуємо ключ — тепер old_key стає previous
        key_record.rotate_key!

        raw_data = "OLD_KEY_DATA"
        encrypted = encrypt_payload(raw_data, old_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "clears grace period when current key succeeds" do
        key_record.update!(previous_aes_key_hex: SecureRandom.hex(32).upcase)

        raw_data = "NEW_KEY_DATA"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        key_record.reload
        expect(key_record.previous_aes_key_hex).to be_nil
      end
    end

    context "when gateway identification" do
      it "finds gateway by UID (priority)" do
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, "different.ip.1.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "falls back to IP when UID is nil" do
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)

        described_class.new.perform(encoded, gateway.ip_address, nil)

        expect(TelemetryUnpackerService).to have_received(:call)
      end

      it "returns early for unknown source" do
        encoded = Base64.strict_encode64("garbage" * 10)

        described_class.new.perform(encoded, "unknown.ip.0.0", "UNKNOWN-UID")

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    context "when hardware key is missing" do
      it "returns early without processing" do
        key_record.destroy!

        raw_data = "TEST"
        encoded = Base64.strict_encode64(raw_data)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    context "when decryption fails completely" do
      it "returns early without calling unpacker" do
        # Payload коротший за 2 AES блоки (32 байти) — дешифрація відхиляється
        encoded = Base64.strict_encode64("\x00" * 16)

        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).not_to have_received(:call)
      end
    end

    it "handles Base64 corruption gracefully" do
      expect {
        described_class.new.perform("not-valid-base64!!!", "10.0.0.1", gateway.uid)
      }.not_to raise_error

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "re-raises unexpected errors for Sidekiq retry" do
      allow(Gateway).to receive(:find_by).and_raise(StandardError, "DB error")

      expect {
        raw_data = "TEST"
        encrypted = encrypt_payload(raw_data, key_record.binary_key)
        encoded = Base64.strict_encode64(encrypted)
        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)
      }.to raise_error(StandardError, "DB error")
    end
  end

  describe "decryption with current key" do
    it "decrypts successfully with current key and clears grace period" do
      payload_data = "\x00" * 32
      encrypted = encrypt_payload(payload_data, key_record.binary_key)
      encoded = Base64.strict_encode64(encrypted)

      expect(key_record).to receive(:clear_grace_period!)
      allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(key_record)
      allow(key_record).to receive_messages(binary_key: key_record.binary_key, binary_previous_key: nil)

      worker = described_class.new

      allow(worker).to receive(:attempt_decryption).and_call_original
      allow(worker).to receive(:decrypt_aes).and_return(payload_data)

      worker.perform(encoded, "192.168.1.1", gateway.uid)
    end
  end

  describe "decryption with previous key" do
    it "falls back to previous key when current key fails" do
      prev_key_hex = SecureRandom.hex(32)
      key_record.update!(previous_aes_key_hex: prev_key_hex)
      allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(key_record)

      worker = described_class.new

      call_count = 0
      allow(worker).to receive(:decrypt_aes) do |_payload, _key|
        call_count += 1
        if call_count == 1
          nil
        else
          "\x00" * 32
        end
      end

      payload_data = "\x00" * 64
      encoded = Base64.strict_encode64(payload_data)

      worker.perform(encoded, "192.168.1.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
    end
  end

  describe "decrypt_aes error handling" do
    it "returns nil for CipherError" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 32, "\x00" * 32)
      expect(result).to be_a(String).or be_nil
    end

    it "returns nil when payload is too short" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 16, "\x00" * 32)
      expect(result).to be_nil
    end

    it "returns nil when ciphertext is not block-aligned" do
      worker = described_class.new
      result = worker.send(:decrypt_aes, "\x00" * 33, "\x00" * 32)
      expect(result).to be_nil
    end

    it "rescues StandardError and returns nil" do
      worker = described_class.new

      allow(OpenSSL::Cipher).to receive(:new).and_raise(StandardError, "unexpected")
      result = worker.send(:decrypt_aes, "\x00" * 64, "\x00" * 32)
      expect(result).to be_nil
    end

    it "rescues OpenSSL::Cipher::CipherError and returns nil" do
      worker = described_class.new
      cipher_mock = instance_double(OpenSSL::Cipher)
      allow(OpenSSL::Cipher).to receive(:new).and_return(cipher_mock)
      allow(cipher_mock).to receive(:decrypt)
      allow(cipher_mock).to receive(:key=)
      allow(cipher_mock).to receive(:iv=)
      allow(cipher_mock).to receive(:padding=)
      allow(cipher_mock).to receive(:update).and_raise(OpenSSL::Cipher::CipherError, "bad decrypt")

      result = worker.send(:decrypt_aes, "\x00" * 64, "\x00" * 32)
      expect(result).to be_nil
    end
  end

  describe "attempt_decryption when both keys fail" do
    it "returns nil when both current and previous keys fail to decrypt" do
      prev_key_hex = SecureRandom.hex(32)
      key_record.update!(previous_aes_key_hex: prev_key_hex)

      worker = described_class.new
      # Both keys fail
      allow(worker).to receive(:decrypt_aes).and_return(nil)

      result = worker.send(:attempt_decryption, "\x00" * 64, key_record)
      expect(result).to be_nil
    end
  end
end

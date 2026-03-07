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

    context "dual-key rotation (grace period)" do
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

    context "gateway identification" do
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
end

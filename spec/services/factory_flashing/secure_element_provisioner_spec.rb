# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::SecureElementProvisioner do
  let(:session)      { build(:provisioning_session, :gilka_b, se_serial_hex: "0123456789ABCDEF01") }
  let(:aes_key_hex)  { "0123456789ABCDEF0123456789ABCDEF" }
  let(:ota_hmac_hex) { "0" * 64 }
  let(:ecc_priv_hex) { "F" * 64 }
  let(:cert_der_hex) { "A" * 100 }

  describe "#provision" do
    it "emits init + serial read + Slot 0 + Slot 3 + lock-config + lock-data when only AES + OTA provided" do
      result = described_class.new(
        session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex
      ).provision

      expect(result.statements.first).to include("atcab_init")
      expect(result.statements).to include(a_string_matching(/Slot 0 AES-128 LoRa/))
      expect(result.statements).to include(a_string_matching(/Slot 3 K_ota \(FW\.23\)/))
      expect(result.statements).to include(a_string_matching(/Slot 1 Ed25519 priv — TODO/))
      expect(result.statements).to include(a_string_matching(/Slot 2 cert — TODO/))
      expect(result.statements).to include("atcab_lock_config_zone()  # irreversible: slot policies frozen")
      expect(result.statements).to include("atcab_lock_data_zone()    # irreversible: all slot writes forbidden forever")
      expect(result.se_serial_hex).to eq("0123456789ABCDEF01")
    end

    it "scrubs raw key bytes from the transcript (anti-leak per 03_06 §5 B)" do
      result = described_class.new(
        session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex
      ).provision

      expect(result.statements.join).not_to include(aes_key_hex)
      expect(result.statements.join).not_to include(ota_hmac_hex)
    end

    it "emits Ed25519 priv statement when ecc_priv_hex is provided" do
      result = described_class.new(
        session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex, ecc_priv_hex: ecc_priv_hex
      ).provision

      expect(result.statements).to include(a_string_matching(/Slot 1 Ed25519 priv/))
      expect(result.statements).not_to include(a_string_matching(/Slot 1 Ed25519 priv — TODO/))
    end

    it "emits cert statement when cert_der_hex is provided" do
      result = described_class.new(
        session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex, cert_der_hex: cert_der_hex
      ).provision

      expect(result.statements).to include(a_string_matching(/Slot 2 X\.509 cert DER$/))
    end

    it "preserves slot-write order so lock-config never precedes any write_zone" do
      result = described_class.new(
        session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex
      ).provision

      lock_idx = result.statements.index("atcab_lock_config_zone()  # irreversible: slot policies frozen")
      write_indices = result.statements.each_with_index.select { |s, _| s.start_with?("atcab_write_zone") }.map(&:last)
      expect(write_indices).to all(be < lock_idx)
    end
  end

  describe "validation" do
    it "rejects Гілка A session" do
      a_session = build(:provisioning_session, gilka: "A")
      expect {
        described_class.new(session: a_session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex)
      }.to raise_error(described_class::InputError, /Гілка B only/)
    end

    it "rejects wrong-sized AES (Slot 0 must be 16B)" do
      expect {
        described_class.new(session: session, aes_key_hex: "F" * 64, ota_hmac_hex: ota_hmac_hex)
      }.to raise_error(described_class::InputError, /Slot 0 AES-128/)
    end

    it "rejects wrong-sized K_ota (Slot 3 must be 32B)" do
      expect {
        described_class.new(session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: "0" * 32)
      }.to raise_error(described_class::InputError, /Slot 3 K_ota/)
    end

    it "rejects non-hex AES" do
      expect {
        described_class.new(session: session, aes_key_hex: "Z" * 32, ota_hmac_hex: ota_hmac_hex)
      }.to raise_error(described_class::InputError, /hexadecimal/)
    end

    it "rejects too-long cert DER" do
      expect {
        described_class.new(
          session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex, cert_der_hex: "A" * 200
        )
      }.to raise_error(described_class::InputError, /Slot 2 cert DER/)
    end

    it "rejects wrong-sized ecc_priv_hex (Slot 1 must be 32B/64hex)" do
      expect {
        described_class.new(
          session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: ota_hmac_hex, ecc_priv_hex: "F" * 32
        )
      }.to raise_error(described_class::InputError, /Slot 1 ECC priv/)
    end

    it "rejects non-hex K_ota (Slot 3 must be hexadecimal)" do
      expect {
        described_class.new(session: session, aes_key_hex: aes_key_hex, ota_hmac_hex: "Z" * 64)
      }.to raise_error(described_class::InputError, /K_ota must be hexadecimal/)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "filter_parameter_logging initializer" do # rubocop:disable RSpec/DescribeClass
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  describe "password-related parameters" do
    it "filters :passw (matches password, passwd, etc.)" do
      result = filter.filter(password: "secret123", passwd: "abc")
      expect(result[:password]).to eq("[FILTERED]")
      expect(result[:passwd]).to eq("[FILTERED]")
    end
  end

  describe "PII parameters" do
    it "filters :email" do
      result = filter.filter(email: "user@example.com")
      expect(result[:email]).to eq("[FILTERED]")
    end
  end

  describe "authentication tokens" do
    it "filters :secret" do
      result = filter.filter(secret: "my_secret")
      expect(result[:secret]).to eq("[FILTERED]")
    end

    it "filters :token" do
      result = filter.filter(token: "abc123", api_token: "xyz789")
      expect(result[:token]).to eq("[FILTERED]")
      expect(result[:api_token]).to eq("[FILTERED]")
    end

    it "filters :otp" do
      result = filter.filter(otp: "123456")
      expect(result[:otp]).to eq("[FILTERED]")
    end
  end

  describe "cryptographic parameters" do
    it "filters :_key (matches aes_key, private_key, etc.)" do
      result = filter.filter(aes_key: "0xDEAD", private_key: "0xBEEF")
      expect(result[:aes_key]).to eq("[FILTERED]")
      expect(result[:private_key]).to eq("[FILTERED]")
    end

    it "filters :crypt" do
      result = filter.filter(encrypted_data: "data", crypt: "stuff")
      expect(result[:crypt]).to eq("[FILTERED]")
    end

    it "filters :salt" do
      result = filter.filter(salt: "random_salt")
      expect(result[:salt]).to eq("[FILTERED]")
    end

    it "filters :certificate" do
      result = filter.filter(certificate: "-----BEGIN CERT-----")
      expect(result[:certificate]).to eq("[FILTERED]")
    end
  end

  describe "financial parameters" do
    it "filters :ssn" do
      result = filter.filter(ssn: "123-45-6789")
      expect(result[:ssn]).to eq("[FILTERED]")
    end

    it "filters :cvv and :cvc" do
      result = filter.filter(cvv: "123", cvc: "456")
      expect(result[:cvv]).to eq("[FILTERED]")
      expect(result[:cvc]).to eq("[FILTERED]")
    end
  end

  describe "SilkenNet-specific sensitive parameters" do
    it "filters :aes_key" do
      result = filter.filter(aes_key: "64hex_aes_key_here")
      expect(result[:aes_key]).to eq("[FILTERED]")
    end

    it "filters :wallet_private_key" do
      result = filter.filter(wallet_private_key: "0xPrivateKeyHere")
      expect(result[:wallet_private_key]).to eq("[FILTERED]")
    end

    it "filters :mnemonic" do
      result = filter.filter(mnemonic: "word1 word2 word3 word4")
      expect(result[:mnemonic]).to eq("[FILTERED]")
    end

    it "filters :binary_payload" do
      result = filter.filter(binary_payload: "\x00\x01\x02")
      expect(result[:binary_payload]).to eq("[FILTERED]")
    end

    it "filters :secret_key" do
      result = filter.filter(secret_key: "hmac_key_here")
      expect(result[:secret_key]).to eq("[FILTERED]")
    end

    it "filters :signature" do
      result = filter.filter(signature: "ed25519_signature_here")
      expect(result[:signature]).to eq("[FILTERED]")
    end

    it "filters :payload" do
      result = filter.filter(payload: "encrypted_telemetry_data")
      expect(result[:payload]).to eq("[FILTERED]")
    end

    it "filters :ed25519_public_key" do
      result = filter.filter(ed25519_public_key: "public_key_here")
      expect(result[:ed25519_public_key]).to eq("[FILTERED]")
    end
  end

  describe "non-sensitive parameters pass through" do
    it "does not filter normal parameters" do
      result = filter.filter(
        name: "Test Tree",
        status: "active",
        bio_status: "homeostasis",
        gateway_uid: "SNET-Q-00000001",
        latitude: 50.4501,
        longitude: 30.5234
      )

      expect(result[:name]).to eq("Test Tree")
      expect(result[:status]).to eq("active")
      expect(result[:bio_status]).to eq("homeostasis")
      expect(result[:gateway_uid]).to eq("SNET-Q-00000001")
      expect(result[:latitude]).to eq(50.4501)
      expect(result[:longitude]).to eq(30.5234)
    end
  end
end

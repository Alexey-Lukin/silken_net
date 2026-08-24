# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Iotex::W3bstreamVerificationService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#verify!" do
    context "when W3bstream credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: "https://w3bstream.example.com", iotex_api_key: "test-api-key-123")
      end

      it "returns a zk_proof_ref on successful verification" do
        response = Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-abc123" }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.verify!

        expect(result).to eq("zk-proof-abc123")
      end

      it "accepts receipt_id as alternative proof reference" do
        response = Web3::HttpClient::Response.new({ "receipt_id" => "receipt-xyz789" }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        service = described_class.new(telemetry_log)
        result = service.verify!

        expect(result).to eq("receipt-xyz789")
      end

      it "sends correct payload to W3bstream" do
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          body = kwargs[:body]
          expect(body[:device_id]).to eq(tree.did)
          expect(body[:peaq_did]).to eq(tree.peaq_did)
          expect(body[:telemetry_log_id]).to eq(telemetry_log.id_value)
          expect(body[:chaotic_data][:z_value]).to be_a(Float)
          expect(body[:hardware_signature]).to be_present
          Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-abc123" }.to_json)
        end

        described_class.new(telemetry_log).verify!
      end

      it "raises VerificationError when W3bstream returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("W3bstream API returned 500: Internal Server Error"))

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /W3bstream API returned 500/)
      end

      it "raises VerificationError when response has no proof reference" do
        response = Web3::HttpClient::Response.new({}.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /не повернув proof reference/)
      end

      it "raises VerificationError on invalid JSON response" do
        response = Web3::HttpClient::Response.new("not json")
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /Invalid JSON response/)
      end

      it "raises VerificationError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("W3bstream connection error: Connection refused"))

        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /W3bstream connection error/)
      end
    end

    context "when iotex_w3bstream_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: nil, iotex_api_key: "test-api-key")
      end

      it "raises VerificationError" do
        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /iotex_w3bstream_url не налаштовано/)
      end
    end

    context "when iotex_api_key is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: "https://w3bstream.example.com", iotex_api_key: nil)
      end

      it "raises VerificationError" do
        service = described_class.new(telemetry_log)

        expect {
          service.verify!
        }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /iotex_api_key не налаштовано/)
      end
    end

    # [S6.13]: SHA256 fallback допустимий лише поза production / WEB3_STRICT_MODE.
    # У production fail-closed: відсутність HardwareKey → VerificationError, бо
    # SHA256 не доводить апаратне походження пакета (anyone with tree.did може
    # підробити «підпис»).
    context "when HardwareKey is missing [S6.13]" do
      before do
        allow(Rails.application.credentials).to receive_messages(iotex_w3bstream_url: "https://w3bstream.example.com", iotex_api_key: "test-api-key-123")
        allow(tree).to receive(:hardware_key).and_return(nil)
      end

      let(:telemetry_log) { create(:telemetry_log, tree: tree) }

      context "when in development/test environment (WEB3_STRICT_MODE unset)" do
        it "logs a warning and proceeds with SHA256 fallback" do
          response = Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-fallback" }.to_json)
          allow(Web3::HttpClient).to receive(:post).and_return(response)
          allow(Rails.logger).to receive(:warn)

          service = described_class.new(telemetry_log)
          expect(service.verify!).to eq("zk-proof-fallback")

          expect(Rails.logger).to have_received(:warn).with(/HardwareKey відсутній.*SHA256 fallback/)
        end

        it "increments W3BSTREAM_SIGNATURE_FALLBACK_TOTAL with reason=missing_hardware_key" do
          response = Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-fallback" }.to_json)
          allow(Web3::HttpClient).to receive(:post).and_return(response)
          counter = SilkenNet::Metrics::W3BSTREAM_SIGNATURE_FALLBACK_TOTAL
          before_count = counter.get(labels: { reason: "missing_hardware_key" }) || 0

          described_class.new(telemetry_log).verify!

          after_count = counter.get(labels: { reason: "missing_hardware_key" })
          expect(after_count).to eq(before_count + 1)
        end
      end

      context "when in production environment" do
        before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production")) }

        it "raises VerificationError (fail-closed) and does not call W3bstream" do
          allow(Web3::HttpClient).to receive(:post)

          service = described_class.new(telemetry_log)

          expect {
            service.verify!
          }.to raise_error(
            Iotex::W3bstreamVerificationService::VerificationError,
            /SHA256 fallback заборонений у production/
          )

          expect(Web3::HttpClient).not_to have_received(:post)
        end

        it "still increments the fallback metric for observability" do
          counter = SilkenNet::Metrics::W3BSTREAM_SIGNATURE_FALLBACK_TOTAL
          before_count = counter.get(labels: { reason: "missing_hardware_key" }) || 0

          expect {
            described_class.new(telemetry_log).verify!
          }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError)

          after_count = counter.get(labels: { reason: "missing_hardware_key" })
          expect(after_count).to eq(before_count + 1)
        end
      end

      context "with WEB3_STRICT_MODE=true outside production" do
        around do |example|
          ENV["WEB3_STRICT_MODE"] = "true"
          example.run
        ensure
          ENV.delete("WEB3_STRICT_MODE")
        end

        it "raises VerificationError (strict mode honored regardless of Rails.env)" do
          service = described_class.new(telemetry_log)

          expect {
            service.verify!
          }.to raise_error(
            Iotex::W3bstreamVerificationService::VerificationError,
            /SHA256 fallback заборонений/
          )
        end
      end
    end

    context "when HardwareKey is present (Ed25519 signature path) [BLOCKER-06]" do
      let(:hardware_key) do
        # Post-ARCH.42: Tree LoRa AES-128 = 16 bytes / 32 hex.
        create(:hardware_key, device_uid: tree.did,
                              aes_key_hex: SecureRandom.hex(16).upcase,
                              lorenz_seed_hex: SecureRandom.hex(32).upcase)
      end

      before do
        hardware_key # ensure created
        tree.reload
        allow(Rails.application.credentials).to receive_messages(
          iotex_w3bstream_url: "https://w3bstream.example.com",
          iotex_api_key: "test-api-key-123"
        )
      end

      it "signs the message with a per-device Ed25519 seed derived via HKDF (post-ARCH.42)" do
        response = Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-ed25519" }.to_json)
        signed_payload = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          signed_payload = kwargs[:body]
          response
        end

        # Post-ARCH.42: Ed25519 seed більше не співпадає з AES key.
        # Окремо derive'ується через HKDF info "silken-ed25519-iotex-v1" (32 bytes).
        # Це усуває key-reuse antipattern: AES key (LoRa AES-128 = 16 bytes) НЕ
        # підходить як Ed25519 seed (потребує рівно 32 bytes).
        expected_seed_hex = HardwareKeyService.derive_iotex_seed(tree.did)
        allow(Ed25519Crypto::SigningService).to receive(:sign)
          .with(expected_seed_hex, kind_of(String))
          .and_call_original

        described_class.new(telemetry_log).verify!

        expect(Ed25519Crypto::SigningService).to have_received(:sign)
          .with(expected_seed_hex, kind_of(String))
        expect(signed_payload[:hardware_signature]).to be_present
      end
    end

    context "with HardwareKey row present but binary_key blank [S6.13]" do
      let(:hardware_key) do
        instance_double(HardwareKey, binary_key: nil)
      end

      before do
        allow(Rails.application.credentials).to receive_messages(
          iotex_w3bstream_url: "https://w3bstream.example.com",
          iotex_api_key: "test-api-key-123"
        )
        allow(tree).to receive(:hardware_key).and_return(hardware_key)
        allow(Web3::HttpClient).to receive(:post).and_return(
          Web3::HttpClient::Response.new({ "proof_id" => "zk-proof-blank-bin" }.to_json)
        )
      end

      it "increments the fallback metric with reason=missing_binary_key" do
        counter = SilkenNet::Metrics::W3BSTREAM_SIGNATURE_FALLBACK_TOTAL
        before_count = counter.get(labels: { reason: "missing_binary_key" }) || 0

        described_class.new(telemetry_log).verify!

        expect(counter.get(labels: { reason: "missing_binary_key" })).to eq(before_count + 1)
      end
    end

    context "with malformed W3bstream proof reference" do
      before do
        allow(Rails.application.credentials).to receive_messages(
          iotex_w3bstream_url: "https://w3bstream.example.com",
          iotex_api_key: "test-api-key-123"
        )
        allow(tree).to receive(:hardware_key).and_return(nil)
        allow(Rails.logger).to receive(:warn)
      end

      it "rejects proof references that violate the ZK_PROOF_REF_PATTERN" do
        response = Web3::HttpClient::Response.new(
          { "proof_id" => "has spaces & symbols!" }.to_json
        )
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect { described_class.new(telemetry_log).verify! }.to raise_error(
          Iotex::W3bstreamVerificationService::VerificationError,
          /невалідний proof reference/
        )
      end
    end
  end
end

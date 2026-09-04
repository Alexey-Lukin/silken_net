# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Peaq::DidRegistryService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    silence_broadcasts!(:tree_map)
    # SEC.22: creds resolve ENV-primary; neutralize ambient .env (dotenv) so these
    # specs deterministically exercise the credentials path regardless of a local .env.
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PEAQ_NODE_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("PEAQ_SIGNING_KEY").and_return(nil)
  end

  # [ARCH.119] One home for «is the leg live»: BOTH values, ENV-first with the credentials
  # fallback (SEC.22). The `before` above already neutralises ambient ENV, so these pins
  # exercise the credentials half — which is the half that is nil in test (no master key),
  # hence each example states its own expectation explicitly rather than trusting silence.
  describe ".configured?" do
    it "is false when both values are absent (the state of every deploy surface today)" do
      allow(Rails.application.credentials).to receive_messages(peaq_node_url: nil, peaq_signing_key: nil)
      expect(described_class.configured?).to be false
    end

    it "is false when only the node URL is set — a key-less leg would still raise per tree" do
      allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: nil)
      expect(described_class.configured?).to be false
    end

    it "is false when only the signing key is set" do
      allow(Rails.application.credentials).to receive_messages(peaq_node_url: nil, peaq_signing_key: "a" * 64)
      expect(described_class.configured?).to be false
    end

    it "is true when both values are present" do
      allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: "a" * 64)
      expect(described_class.configured?).to be true
    end

    it "reads the SAME expression the raise-path reads (one home, no drift)" do
      allow(ENV).to receive(:[]).with("PEAQ_NODE_URL").and_return("https://from-env.example.com")
      allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://from-creds.example.com", peaq_signing_key: "a" * 64)

      expect(described_class.node_url).to eq("https://from-env.example.com")
      expect(described_class.configured?).to be true
    end
  end

  describe "#register!" do
    context "when peaq_node_url is configured" do
      before do
        # [BLOCKER-08]: peaq_signing_key is now mandatory — stub it for all tests
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: "a" * 64)
        allow(Ed25519Crypto::SigningService).to receive_messages(sign: "sig_hex", public_key_from_seed: "pub_hex")
        allow(Web3::HttpClient).to receive(:post)
          .and_return(Web3::HttpClient::Response.new("{}"))
      end

      it "returns a peaq DID string with correct prefix" do
        service = described_class.new(tree)
        result = service.register!

        expect(result).to start_with("did:peaq:0x")
        expect(result.length).to eq(51) # "did:peaq:0x" (11) + 40 hex chars
      end

      it "generates deterministic DID based on tree attributes" do
        service = described_class.new(tree)
        did1 = service.register!
        did2 = service.register!

        expect(did1).to eq(did2)
      end

      it "raises RegistrationError when peaq node returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("peaq DID API returned 500: Internal Server Error"))

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq DID API returned 500/)
      end

      it "raises RegistrationError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("peaq DID connection error: Connection refused"))

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq DID connection error/)
      end
    end

    context "when both ENV and credentials are set (SEC.22 — ENV wins)" do
      before do
        allow(ENV).to receive(:[]).with("PEAQ_NODE_URL").and_return("https://env-node.example.com")
        allow(ENV).to receive(:[]).with("PEAQ_SIGNING_KEY").and_return("e" * 64)
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://cred-node.example.com", peaq_signing_key: "c" * 64)
        allow(Ed25519Crypto::SigningService).to receive_messages(sign: "sig", public_key_from_seed: "pub")
        allow(Web3::HttpClient).to receive(:post).and_return(Web3::HttpClient::Response.new("{}"))
      end

      it "signs with the ENV signing key, not the credentials key" do
        described_class.new(tree).register!
        expect(Ed25519Crypto::SigningService).to have_received(:sign).with("e" * 64, anything)
      end
    end

    context "when peaq_node_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: nil, peaq_signing_key: "a" * 64)
      end

      it "raises RegistrationError" do
        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq_node_url не налаштовано/)
      end
    end

    context "when peaq_signing_key is not configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: nil)
      end

      it "raises RegistrationError about mandatory peaq_signing_key" do
        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq_signing_key обов'язковий/)
      end
    end

    context "when peaq_signing_key is configured" do
      before do
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: "a" * 64)
      end

      it "includes Ed25519 proof in registration payload" do
        allow(Ed25519Crypto::SigningService).to receive_messages(sign: "sig_hex", public_key_from_seed: "pub_hex")
        allow(Web3::HttpClient).to receive(:post)
          .and_return(Web3::HttpClient::Response.new("{}"))

        service = described_class.new(tree)
        result = service.register!
        expect(result).to start_with("did:peaq:0x")

        expect(Web3::HttpClient).to have_received(:post).with(
          anything,
          hash_including(body: hash_including(:proof))
        )
      end
    end

    context "when peaq_signing_key is invalid" do
      before do
        allow(Rails.application.credentials).to receive_messages(peaq_node_url: "https://peaq-node.example.com", peaq_signing_key: "invalid_key")
      end

      it "raises RegistrationError on Ed25519 signing failure" do
        allow(Ed25519Crypto::SigningService).to receive(:sign).and_raise(
          Ed25519Crypto::SigningService::SigningError, "bad key"
        )

        service = described_class.new(tree)
        expect { service.register! }.to raise_error(
          Peaq::DidRegistryService::RegistrationError, /Invalid peaq_signing_key/
        )
      end
    end
  end
end

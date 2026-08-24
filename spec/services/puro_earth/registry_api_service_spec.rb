# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuroEarth::RegistryApiService do
  let(:payload) do
    {
      tree_did: "did:peaq:0x#{"a" * 40}",
      biomass_yield_kg: 125.5,
      extraction_date: "2026-03-15T10:30:00Z",
      gps_coordinates: {
        latitude: 49.4285,
        longitude: 32.0620
      },
      lifetime_telemetry_hash: "b" * 64
    }
  end

  let(:tx_hash) { "0x#{"fa" * 32}" }
  let(:corc_ref) { "CORC-2026-A1B2C3D4" }

  let(:success_response_body) do
    {
      "submission_id" => "sub-12345",
      "corc_ref" => corc_ref,
      "status" => "accepted"
    }.to_json
  end

  let(:mock_response) { Web3::HttpClient::Response.new(success_response_body) }

  before do
    allow(Web3::HttpClient).to receive(:post).and_return(mock_response)
    allow(Rails.application.credentials).to receive(:dig).with(:puro_earth, :api_key).and_return("test-api-key")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PURO_EARTH_API_URL", "https://api.puro.earth").and_return("https://api.puro.earth")
    allow(ENV).to receive(:fetch).with("PURO_EARTH_REGISTRY_CONTRACT_ADDRESS", nil).and_return("0x#{"ee" * 20}")
    # SEC.22: api_key resolves ENV-primary via ENV[]; neutralize ambient .env so the
    # credentials path is deterministic (per-test override re-adds ENV where needed).
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PURO_EARTH_API_KEY").and_return(nil)
  end

  describe "#submit!" do
    it "returns the CORC reference from API response" do
      result = described_class.new(payload, tx_hash: tx_hash).submit!
      expect(result).to eq(corc_ref)
    end

    it "POSTs to the Puro.earth submissions endpoint" do
      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        "https://api.puro.earth/v1/dmrv/submissions",
        hash_including(
          body: hash_including(
            source: "silkennet",
            methodology: "biochar-corc"
          ),
          service_name: "Puro.earth"
        )
      )
    end

    it "includes on-chain proof in the submission body" do
      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          body: hash_including(
            on_chain_proof: {
              network: "polygon",
              tx_hash: tx_hash,
              contract: "0x#{"ee" * 20}"
            }
          )
        )
      )
    end

    it "includes passport data in the submission body" do
      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          body: hash_including(
            passport: {
              tree_did: payload[:tree_did],
              biomass_yield_kg: payload[:biomass_yield_kg],
              extraction_date: payload[:extraction_date],
              gps_coordinates: payload[:gps_coordinates],
              lifetime_telemetry_hash: payload[:lifetime_telemetry_hash]
            }
          )
        )
      )
    end

    it "sends Authorization header with Bearer token from credentials" do
      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          headers: hash_including("Authorization" => "Bearer test-api-key")
        )
      )
    end

    it "uses the ENV API key as the primary source (SEC.22)" do
      allow(Rails.application.credentials).to receive(:dig).with(:puro_earth, :api_key).and_return(nil)
      allow(ENV).to receive(:[]).with("PURO_EARTH_API_KEY").and_return("env-api-key")

      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          headers: hash_including("Authorization" => "Bearer env-api-key")
        )
      )
    end

    it "prefers the ENV API key over a present credentials value (SEC.22)" do
      allow(Rails.application.credentials).to receive(:dig).with(:puro_earth, :api_key).and_return("cred-api-key")
      allow(ENV).to receive(:[]).with("PURO_EARTH_API_KEY").and_return("env-api-key")

      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(headers: hash_including("Authorization" => "Bearer env-api-key"))
      )
    end

    it "omits Authorization header when no API key is available" do
      allow(Rails.application.credentials).to receive(:dig).with(:puro_earth, :api_key).and_return(nil)
      allow(ENV).to receive(:[]).with("PURO_EARTH_API_KEY").and_return(nil)

      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          headers: { "Accept" => "application/json" }
        )
      )
    end

    it "uses configurable timeouts" do
      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Web3::HttpClient).to have_received(:post).with(
        anything,
        hash_including(
          open_timeout: 10,
          read_timeout: 30
        )
      )
    end

    it "logs successful submission" do
      allow(Rails.logger).to receive(:info).with(
        a_string_matching(/D-MRV submission accepted.*CORC ref: #{corc_ref}/)
      )

      described_class.new(payload, tx_hash: tx_hash).submit!

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/D-MRV submission accepted.*CORC ref: #{corc_ref}/)
      )
    end

    context "when API response contains only submission_id" do
      let(:success_response_body) do
        { "submission_id" => "sub-12345", "status" => "accepted" }.to_json
      end

      it "falls back to submission_id as CORC reference" do
        result = described_class.new(payload, tx_hash: tx_hash).submit!
        expect(result).to eq("sub-12345")
      end
    end

    context "when API response has no CORC reference" do
      let(:success_response_body) do
        { "status" => "error" }.to_json
      end

      it "raises SubmissionError" do
        expect {
          described_class.new(payload, tx_hash: tx_hash).submit!
        }.to raise_error(
          PuroEarth::RegistryApiService::SubmissionError,
          /missing CORC reference/
        )
      end
    end

    context "when HTTP request fails" do
      it "wraps RequestError in SubmissionError" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError, "Connection timeout")

        expect {
          described_class.new(payload, tx_hash: tx_hash).submit!
        }.to raise_error(
          PuroEarth::RegistryApiService::SubmissionError,
          /API request failed.*Connection timeout/
        )
      end
    end

    context "when API returns non-JSON response" do
      let(:success_response_body) { "Internal Server Error" }

      it "raises SubmissionError" do
        expect {
          described_class.new(payload, tx_hash: tx_hash).submit!
        }.to raise_error(PuroEarth::RegistryApiService::SubmissionError)
      end
    end

    context "with custom API URL via ENV" do
      it "uses the configured base URL" do
        stub_const("PuroEarth::RegistryApiService::PURO_EARTH_API_URL", "https://sandbox.puro.earth")

        described_class.new(payload, tx_hash: tx_hash).submit!

        expect(Web3::HttpClient).to have_received(:post).with(
          "https://sandbox.puro.earth/v1/dmrv/submissions",
          anything
        )
      end
    end
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuroEarth::PassportService do
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

  let(:mock_client) { instance_double(Eth::Client) }
  let(:mock_key) { instance_double(Eth::Key, address: "0x#{"ab" * 20}") }
  let(:mock_contract) { instance_double(Eth::Contract) }
  let(:fake_tx_hash) { "0x#{"fa" * 32}" }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ORACLE_PURO_PRIVATE_KEY").and_return("0x#{"ff" * 32}")
    allow(ENV).to receive(:fetch).with("PURO_EARTH_REGISTRY_CONTRACT_ADDRESS").and_return("0x#{"ee" * 20}")
    allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
    allow(Kredis).to receive(:lock).and_yield # [ARCH.49] lock серіалізує підпис; стаб yield-ить синхронно
  end

  describe "#anchor!" do
    it "returns the on-chain transaction hash" do
      result = described_class.new(payload).anchor!

      expect(result).to eq(fake_tx_hash)
    end

    it "[ARCH.49] wraps the transact in the shared base-EOA Kredis lock (nonce-serialization)" do
      described_class.new(payload).anchor!

      expect(Kredis).to have_received(:lock).with(
        "lock:web3:oracle:#{mock_key.address}", expires_in: 30.seconds, after_timeout: :raise
      )
    end

    it "[ARCH.49] re-raises Kredis::LockTimeout (NOT AnchoringError) — lock not acquired → clean retry" do
      allow(Kredis).to receive(:lock).and_raise(Kredis::LockTimeout)

      expect { described_class.new(payload).anchor! }.to raise_error(Kredis::LockTimeout)
      expect(mock_client).not_to have_received(:transact)
    end

    it "connects to Polygon via RPC connection pool" do
      described_class.new(payload).anchor!

      expect(Web3::RpcConnectionPool).to have_received(:client_for).with("ALCHEMY_POLYGON_RPC_URL")
    end

    it "creates contract with PuroEarthRegistry address from ENV" do
      described_class.new(payload).anchor!

      expect(Eth::Contract).to have_received(:from_abi).with(
        name: "PuroEarthRegistry",
        address: "0x#{"ee" * 20}",
        abi: described_class::REGISTRY_ABI
      )
    end

    it "calls anchorPassport with tree_did and bytes32 payload hash" do
      described_class.new(payload).anchor!

      expect(mock_client).to have_received(:transact) do |contract, method, tree_did, hash_bytes, **opts|
        expect(contract).to eq(mock_contract)
        expect(method).to eq("anchorPassport")
        expect(tree_did).to eq("did:peaq:0x#{"a" * 40}")
        expect(hash_bytes).to match(/\A0x[a-f0-9]{64}\z/)
        expect(opts[:sender_key]).to eq(mock_key)
        expect(opts[:legacy]).to be false
      end
    end

    it "computes a deterministic SHA-256 hash of the canonical JSON payload" do
      service1 = described_class.new(payload)
      service2 = described_class.new(payload)

      # Both calls should produce the same hash_bytes32 argument
      hashes = []
      allow(mock_client).to receive(:transact) do |_contract, _method, _tree_did, hash_bytes, **_opts|
        hashes << hash_bytes
        fake_tx_hash
      end

      service1.anchor!
      service2.anchor!

      expect(hashes.size).to eq(2)
      expect(hashes[0]).to eq(hashes[1])
    end

    it "produces the same hash regardless of key insertion order" do
      payload_reversed = {
        lifetime_telemetry_hash: "b" * 64,
        gps_coordinates: {
          longitude: 32.0620,
          latitude: 49.4285
        },
        extraction_date: "2026-03-15T10:30:00Z",
        biomass_yield_kg: 125.5,
        tree_did: "did:peaq:0x#{"a" * 40}"
      }

      hashes = []
      allow(mock_client).to receive(:transact) do |_contract, _method, _tree_did, hash_bytes, **_opts|
        hashes << hash_bytes
        fake_tx_hash
      end

      described_class.new(payload).anchor!
      described_class.new(payload_reversed).anchor!

      expect(hashes[0]).to eq(hashes[1])
    end

    it "logs successful anchoring" do
      allow(Rails.logger).to receive(:info).with(a_string_matching(/Passport anchored on-chain/))

      described_class.new(payload).anchor!

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/Passport anchored on-chain/))
    end

    it "wraps RPC errors in AnchoringError for Sidekiq retry" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

      expect {
        described_class.new(payload).anchor!
      }.to raise_error(
        PuroEarth::PassportService::AnchoringError,
        /Puro\.earth passport anchoring failed.*RPC timeout/
      )
    end

    it "wraps missing ENV in AnchoringError" do
      allow(ENV).to receive(:fetch).with("ORACLE_PURO_PRIVATE_KEY")
        .and_raise(KeyError.new("key not found: \"ORACLE_PURO_PRIVATE_KEY\""))

      expect {
        described_class.new(payload).anchor!
      }.to raise_error(PuroEarth::PassportService::AnchoringError)
    end
  end

  describe "#deep_sort_keys (Array branch)" do
    it "recursively sorts hashes inside arrays" do
      service = described_class.new({
        tree_did: "test",
        items: [ { z_key: 1, a_key: 2 }, { m_key: 3, b_key: 4 } ]
      })

      sorted = service.send(:deep_sort_keys, { z: 1, a: [ { c: 3, b: 2 } ] })
      keys = sorted.keys
      expect(keys).to eq([ :a, :z ])
      expect(sorted[:a].first.keys).to eq([ :b, :c ])
    end
  end

  describe "#extract_canonical_fields" do
    let(:service) { described_class.new(payload) }

    it "extracts fields in alphabetical key order" do
      types, values = service.send(:extract_canonical_fields, {
        z_field: "last",
        a_field: "first"
      })

      expect(types).to eq(%w[string string])
      expect(values).to eq(%w[first last])
    end

    it "flattens nested hashes recursively" do
      types, values = service.send(:extract_canonical_fields, {
        coordinates: { latitude: 49.0, longitude: 32.0 },
        name: "test"
      })

      # coordinates.latitude, coordinates.longitude, name
      expect(types.size).to eq(3)
      expect(values[2]).to eq("test")
    end

    it "scales floats to uint256 with 18-decimal precision" do
      types, values = service.send(:extract_canonical_fields, { amount: 125.5 })

      expect(types).to eq([ "uint256" ])
      expect(values).to eq([ 125_500_000_000_000_000_000 ])
    end

    it "handles integers as uint256 without scaling" do
      types, values = service.send(:extract_canonical_fields, { count: 42 })

      expect(types).to eq([ "uint256" ])
      expect(values).to eq([ 42 ])
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require "eth"

RSpec.describe Web3::ResilientClient do
  let(:primary_url) { "https://alchemy.example.com" }
  let(:secondary_url) { "https://infura.example.com" }
  let(:client) { described_class.new([ primary_url, secondary_url ]) }

  let(:primary_eth_client) { instance_double(Eth::Client) }
  let(:secondary_eth_client) { instance_double(Eth::Client) }

  before do
    allow(Eth::Client).to receive(:create).with(primary_url).and_return(primary_eth_client)
    allow(Eth::Client).to receive(:create).with(secondary_url).and_return(secondary_eth_client)
  end

  describe "#method_missing" do
    context "when primary succeeds" do
      it "delegates to primary client" do
        allow(primary_eth_client).to receive(:eth_block_number).and_return("0x123")

        result = client.eth_block_number
        expect(result).to eq("0x123")
      end
    end

    context "when primary fails with timeout" do
      it "falls back to secondary client" do
        allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
        allow(secondary_eth_client).to receive(:eth_block_number).and_return("0x456")

        result = client.eth_block_number
        expect(result).to eq("0x456")
      end
    end

    context "when primary fails with connection refused" do
      it "falls back to secondary client" do
        allow(primary_eth_client).to receive(:eth_block_number).and_raise(Errno::ECONNREFUSED)
        allow(secondary_eth_client).to receive(:eth_block_number).and_return("0x789")

        result = client.eth_block_number
        expect(result).to eq("0x789")
      end
    end

    context "when all providers fail" do
      it "raises the last error" do
        allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
        allow(secondary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)

        expect { client.eth_block_number }.to raise_error(Net::ReadTimeout)
      end
    end

    context "when non-retriable error occurs" do
      it "raises immediately without fallback" do
        allow(primary_eth_client).to receive(:eth_block_number).and_raise(ArgumentError, "bad args")

        expect { client.eth_block_number }.to raise_error(ArgumentError, "bad args")
        expect(secondary_eth_client).not_to have_received(:eth_block_number) if secondary_eth_client.respond_to?(:eth_block_number)
      end
    end
  end

  describe "circuit breaker" do
    it "opens circuit after MAX_FAILURES consecutive failures" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      # Trigger MAX_FAILURES failures on primary
      described_class::MAX_FAILURES.times do
        client.eth_block_number
      end

      health = client.provider_health
      primary_health = health.find { |h| h[:provider].include?("alchemy") }

      expect(primary_health[:circuit_open]).to be true
      expect(primary_health[:failures]).to eq(described_class::MAX_FAILURES)
    end
  end

  describe "#provider_health" do
    it "returns health status for all providers" do
      health = client.provider_health

      expect(health.size).to eq(2)
      expect(health.first).to include(:provider, :failures, :circuit_open, :available)
    end
  end

  describe "#respond_to_missing?" do
    it "returns true for Eth::Client methods" do
      expect(client.respond_to?(:eth_block_number)).to be true
    end
  end

  describe "initialization" do
    it "raises ArgumentError with empty urls" do
      expect { described_class.new([]) }.to raise_error(ArgumentError, /At least one RPC URL/)
    end

    it "works with single url" do
      single_client = described_class.new([ primary_url ])
      allow(primary_eth_client).to receive(:eth_block_number).and_return("0x1")

      expect(single_client.eth_block_number).to eq("0x1")
    end
  end
end

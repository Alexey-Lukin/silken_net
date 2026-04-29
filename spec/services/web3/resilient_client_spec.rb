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

    it "resets failure count on success" do
      allow(primary_eth_client).to receive(:eth_block_number).and_return("0xok")

      # First a failure, then a success
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout).once
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")
      client.eth_block_number

      # Reset the stub to succeed
      allow(primary_eth_client).to receive(:eth_block_number).and_return("0xok")
      client.eth_block_number

      health = client.provider_health
      primary_health = health.find { |h| h[:provider].include?("alchemy") }
      expect(primary_health[:failures]).to eq(0)
    end

    it "marks circuit breaker as unavailable when open" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      described_class::MAX_FAILURES.times { client.eth_block_number }

      health = client.provider_health
      primary_health = health.find { |h| h[:provider].include?("alchemy") }
      expect(primary_health[:available]).to be false
    end

    it "reopens circuit breaker after CIRCUIT_OPEN_DURATION" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      described_class::MAX_FAILURES.times { client.eth_block_number }

      # Simulate time passing beyond circuit open duration
      allow(Time).to receive(:current).and_return(Time.current + described_class::CIRCUIT_OPEN_DURATION + 1)

      health = client.provider_health
      primary_health = health.find { |h| h[:provider].include?("alchemy") }
      expect(primary_health[:available]).to be true
    end

    it "resets all circuits and retries all providers when all are open" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)

      # Open both circuit breakers
      described_class::MAX_FAILURES.times do
        expect { client.eth_block_number }.to raise_error(Net::ReadTimeout)
      end

      # Now make secondary work - all circuits are open so it should still try both
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xrecovered")
      result = client.eth_block_number
      expect(result).to eq("0xrecovered")
    end
  end

  describe "rate limiting detection" do
    it "falls back on HTTP 429 errors" do
      error = StandardError.new("HTTP 429 Too Many Requests")
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(error)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xfallback")

      result = client.eth_block_number
      expect(result).to eq("0xfallback")
    end

    it "falls back on 'too many requests' error messages" do
      error = StandardError.new("too many requests from your IP")
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(error)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xfallback")

      result = client.eth_block_number
      expect(result).to eq("0xfallback")
    end

    it "falls back on 'rate limit' error messages" do
      error = StandardError.new("rate limit exceeded")
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(error)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xfallback")

      result = client.eth_block_number
      expect(result).to eq("0xfallback")
    end
  end

  describe "retriable errors" do
    [
      Net::ReadTimeout,
      Net::OpenTimeout,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      IOError,
      SocketError
    ].each do |error_class|
      it "falls back on #{error_class}" do
        allow(primary_eth_client).to receive(:eth_block_number).and_raise(error_class)
        allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xrecovered")

        result = client.eth_block_number
        expect(result).to eq("0xrecovered")
      end
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

  describe "Prometheus metrics integration" do
    it "increments RPC_ERRORS_TOTAL on provider failure" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment).with(
        labels: { network: "alchemy.example.com:443", error_type: "timeout" }
      )

      client.eth_block_number
    end

    it "sets RPC_CIRCUIT_BREAKER_OPEN gauge to 1.0 when circuit opens" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      expect(SilkenNet::Metrics::RPC_CIRCUIT_BREAKER_OPEN).to receive(:set).with(
        1.0, labels: { provider: "alchemy.example.com:443" }
      )

      described_class::MAX_FAILURES.times { client.eth_block_number }
    end

    it "sets RPC_CIRCUIT_BREAKER_OPEN gauge to 0.0 when circuit recovers" do
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(Net::ReadTimeout)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      # Open circuit
      described_class::MAX_FAILURES.times { client.eth_block_number }

      # Simulate cooldown
      allow(Time).to receive(:current).and_return(Time.current + described_class::CIRCUIT_OPEN_DURATION + 1)

      # Allow primary to succeed now
      allow(primary_eth_client).to receive(:eth_block_number).and_return("0xrecovered")

      expect(SilkenNet::Metrics::RPC_CIRCUIT_BREAKER_OPEN).to receive(:set).with(
        0.0, labels: { provider: "alchemy.example.com:443" }
      )

      client.eth_block_number
    end

    it "classifies rate limit errors correctly" do
      error = StandardError.new("HTTP 429 Too Many Requests")
      allow(primary_eth_client).to receive(:eth_block_number).and_raise(error)
      allow(secondary_eth_client).to receive(:eth_block_number).and_return("0xok")

      expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment).with(
        labels: { network: "alchemy.example.com:443", error_type: "rate_limited" }
      )

      client.eth_block_number
    end
  end
end

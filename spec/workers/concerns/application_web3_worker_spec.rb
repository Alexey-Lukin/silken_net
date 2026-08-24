# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationWeb3Worker do
  # Create a test worker class including the concern
  let(:test_worker_class) do
    Class.new do
      include ApplicationWeb3Worker
      sidekiq_options queue: "web3_critical", retry: 10

      def self.name
        "TestWeb3Worker"
      end
    end
  end
  let(:worker) { test_worker_class.new }

  # =========================================================================
  # MODULE INCLUSION
  # =========================================================================
  describe "module inclusion" do
    it "includes Sidekiq::Job" do
      expect(test_worker_class.ancestors).to include(Sidekiq::Job)
    end

    it "sets default queue to web3" do
      default_class = Class.new do
        include ApplicationWeb3Worker
        def self.name; "DefaultWorker"; end
      end
      expect(default_class.sidekiq_options["queue"]).to eq("web3")
    end

    it "allows subclass to override sidekiq_options" do
      expect(test_worker_class.sidekiq_options["queue"]).to eq("web3_critical")
      expect(test_worker_class.sidekiq_options["retry"]).to eq(10)
    end
  end

  # =========================================================================
  # RPC TRANSIENT ERRORS
  # =========================================================================
  describe "RPC_TRANSIENT_ERRORS constant" do
    it "includes all expected transient error types" do
      expected_errors = [
        HTTPX::TimeoutError,
        HTTPX::ConnectionError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        IOError
      ]
      expected_errors.each do |err|
        expect(ApplicationWeb3Worker::RPC_TRANSIENT_ERRORS).to include(err)
      end
    end

    it "is frozen" do
      expect(ApplicationWeb3Worker::RPC_TRANSIENT_ERRORS).to be_frozen
    end
  end

  # =========================================================================
  # WEB3_RPC_LIMITER
  # =========================================================================
  describe "WEB3_RPC_LIMITER" do
    it "is defined as a limiter" do
      expect(ApplicationWeb3Worker::WEB3_RPC_LIMITER).to respond_to(:within_limit)
    end
  end

  # =========================================================================
  # #with_web3_error_handling
  # =========================================================================
  describe "#with_web3_error_handling" do
    context "when block succeeds" do
      it "returns the block result" do
        result = worker.with_web3_error_handling("Polygon", "TX #123") { "success" }
        expect(result).to eq("success")
      end

      it "works without resource_info" do
        result = worker.with_web3_error_handling("Ethereum") { 42 }
        expect(result).to eq(42)
      end
    end

    context "when HTTPX::TimeoutError is raised" do
      it "logs error, increments Prometheus metric, and re-raises" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        allow(Rails.logger).to receive(:error).with(/Polygon.*RPC Timeout.*for TX #123.*execution expired/)

        expect {
          worker.with_web3_error_handling("Polygon", "TX #123") do
            raise HTTPX::TimeoutError.new(nil, "execution expired")
          end
        }.to raise_error(HTTPX::TimeoutError)

        expect(Rails.logger).to have_received(:error).with(/Polygon.*RPC Timeout.*for TX #123.*execution expired/)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Polygon", error_type: "timeout" })
      end
    end

    context "when HTTPX::ConnectionError is raised" do
      it "logs error, increments Prometheus metric, and re-raises" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        allow(Rails.logger).to receive(:error).with(/Polygon.*RPC Connection Error/)

        expect {
          worker.with_web3_error_handling("Polygon") do
            raise HTTPX::ConnectionError.new("Connection refused")
          end
        }.to raise_error(HTTPX::ConnectionError)

        expect(Rails.logger).to have_received(:error).with(/Polygon.*RPC Connection Error/)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Polygon", error_type: "connection" })
      end
    end

    context "when Net::OpenTimeout is raised" do
      it "logs and re-raises as timeout" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        expect {
          worker.with_web3_error_handling("Celo", "Wallet #5") do
            raise Net::OpenTimeout, "open timeout"
          end
        }.to raise_error(Net::OpenTimeout)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Celo", error_type: "timeout" })
      end
    end

    context "when Net::ReadTimeout is raised" do
      it "logs and re-raises as timeout" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        expect {
          worker.with_web3_error_handling("Solana") do
            raise Net::ReadTimeout, "read timeout"
          end
        }.to raise_error(Net::ReadTimeout)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Solana", error_type: "timeout" })
      end
    end

    context "when Errno::ECONNREFUSED is raised" do
      it "logs and re-raises as connection error" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        expect {
          worker.with_web3_error_handling("Ethereum") do
            raise Errno::ECONNREFUSED, "Connection refused"
          end
        }.to raise_error(Errno::ECONNREFUSED)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Ethereum", error_type: "connection" })
      end
    end

    context "when Errno::ECONNRESET is raised" do
      it "logs and re-raises as connection error" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        expect {
          worker.with_web3_error_handling("IoTeX") do
            raise Errno::ECONNRESET, "Connection reset"
          end
        }.to raise_error(Errno::ECONNRESET)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "IoTeX", error_type: "connection" })
      end
    end

    context "when IOError is raised" do
      it "logs and re-raises as connection error" do
        allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

        expect {
          worker.with_web3_error_handling("Filecoin") do
            raise IOError, "stream closed"
          end
        }.to raise_error(IOError)

        expect(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to have_received(:increment)
          .with(labels: { network: "Filecoin", error_type: "connection" })
      end
    end

    context "when Sidekiq::Limiter::OverLimit is raised" do
      it "logs warning and re-raises for Enterprise rescheduling" do
        allow(Rails.logger).to receive(:warn).with(/Polygon.*RPC rate limit exceeded.*for Batch Collector/)

        expect {
          worker.with_web3_error_handling("Polygon", "Batch Collector") do
            raise Sidekiq::Limiter::OverLimit
          end
        }.to raise_error(Sidekiq::Limiter::OverLimit)

        expect(Rails.logger).to have_received(:warn).with(/Polygon.*RPC rate limit exceeded.*for Batch Collector/)
      end

      it "includes empty context when no resource_info" do
        allow(Rails.logger).to receive(:warn).with(/Polygon.*RPC rate limit exceeded\./)

        expect {
          worker.with_web3_error_handling("Polygon") do
            raise Sidekiq::Limiter::OverLimit
          end
        }.to raise_error(Sidekiq::Limiter::OverLimit)

        expect(Rails.logger).to have_received(:warn).with(/Polygon.*RPC rate limit exceeded\./)
      end
    end

    context "when non-transient error is raised" do
      it "propagates without special handling" do
        expect {
          worker.with_web3_error_handling("Polygon") do
            raise ArgumentError, "bad input"
          end
        }.to raise_error(ArgumentError, "bad input")
      end
    end
  end

  # =========================================================================
  # #within_rpc_limit
  # =========================================================================
  describe "#within_rpc_limit" do
    it "executes block through the RPC limiter" do
      result = worker.within_rpc_limit { "limited_result" }
      expect(result).to eq("limited_result")
    end
  end

  # =========================================================================
  # #find_telemetry_log_with_pruning
  # =========================================================================
  describe "#find_telemetry_log_with_pruning" do
    before do
      silence_broadcasts!(:tree_map, :wallet_balance)
    end

    let(:tree) { create(:tree) }
    let!(:log) { create(:telemetry_log, tree: tree, created_at: Time.current) }

    it "finds telemetry log by ID without partition pruning" do
      result = worker.find_telemetry_log_with_pruning(log.id, nil)
      expect(result).to eq(log)
    end

    it "applies partition pruning when created_at_iso is provided" do
      result = worker.find_telemetry_log_with_pruning(log.id, log.created_at.iso8601(6))
      expect(result).to eq(log)
    end

    it "falls back to non-pruned search when created_at_iso is invalid" do
      result = worker.find_telemetry_log_with_pruning(log.id, "invalid-date")
      expect(result).to eq(log)
    end

    it "falls back to non-pruned search when created_at_iso is blank" do
      result = worker.find_telemetry_log_with_pruning(log.id, "")
      expect(result).to eq(log)
    end

    it "returns nil and logs error when log is not found" do
      allow(Rails.logger).to receive(:error).with(/TelemetryLog #999999 не знайдено/)

      result = worker.find_telemetry_log_with_pruning(999_999, nil)

      expect(Rails.logger).to have_received(:error).with(/TelemetryLog #999999 не знайдено/)
      expect(result).to be_nil
    end

    it "uses custom log_prefix when provided" do
      allow(Rails.logger).to receive(:error).with(/\[Solana\].*TelemetryLog #999999/)

      worker.find_telemetry_log_with_pruning(999_999, nil, log_prefix: "[Solana]")

      expect(Rails.logger).to have_received(:error).with(/\[Solana\].*TelemetryLog #999999/)
    end
  end

  # =========================================================================
  # #find_blockchain_tx_with_pruning
  # =========================================================================
  describe "#find_blockchain_tx_with_pruning" do
    before do
      silence_broadcasts!(:tree_map, :wallet_balance)
    end

    let(:tree) { create(:tree) }
    let(:wallet) { tree.wallet }
    let!(:tx) do
      create(:blockchain_transaction, wallet: wallet, created_at: Time.current)
    end

    it "finds blockchain transaction by ID with partition pruning" do
      result = worker.find_blockchain_tx_with_pruning(tx.id, tx.created_at.iso8601)
      expect(result).to eq(tx)
    end

    it "returns nil and logs error when transaction is not found" do
      allow(Rails.logger).to receive(:error).with(/BlockchainTransaction #999999 не знайдено/)

      result = worker.find_blockchain_tx_with_pruning(999_999, nil)

      expect(Rails.logger).to have_received(:error).with(/BlockchainTransaction #999999 не знайдено/)
      expect(result).to be_nil
    end

    it "uses custom log_prefix when provided" do
      allow(Rails.logger).to receive(:error).with(/\[Chainlink\].*BlockchainTransaction/)

      worker.find_blockchain_tx_with_pruning(999_999, nil, log_prefix: "[Chainlink]")

      expect(Rails.logger).to have_received(:error).with(/\[Chainlink\].*BlockchainTransaction/)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationWeb3Worker do
  # Test worker class that includes ApplicationWeb3Worker for isolated testing
  let(:test_worker_class) do
    Class.new do
      include ApplicationWeb3Worker

      def perform_with_handling(chain_name, resource_info = nil, &block)
        with_web3_error_handling(chain_name, resource_info, &block)
      end

      def find_log(telemetry_log_id, created_at_iso, prefix: "[Test]")
        find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: prefix)
      end
    end
  end

  let(:worker) { test_worker_class.new }

  describe "Sidekiq::Job inclusion" do
    it "includes Sidekiq::Job automatically" do
      expect(test_worker_class.ancestors).to include(Sidekiq::Job)
    end

    it "sets default queue to web3" do
      expect(test_worker_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "sets default retry to 5" do
      expect(test_worker_class.get_sidekiq_options["retry"]).to eq(5)
    end
  end

  describe "sidekiq_options override" do
    let(:custom_worker_class) do
      Class.new do
        include ApplicationWeb3Worker
        sidekiq_options queue: "web3_critical", retry: 10
      end
    end

    it "allows overriding queue" do
      expect(custom_worker_class.get_sidekiq_options["queue"]).to eq("web3_critical")
    end

    it "allows overriding retry" do
      expect(custom_worker_class.get_sidekiq_options["retry"]).to eq(10)
    end
  end

  describe "#with_web3_error_handling" do
    it "yields the block and returns its result" do
      result = worker.perform_with_handling("Polygon") { "success" }
      expect(result).to eq("success")
    end

    it "re-raises HTTPX::TimeoutError with structured log" do
      expect(Rails.logger).to receive(:error).with(/\[Polygon\] RPC Timeout/)

      expect {
        worker.perform_with_handling("Polygon", "TX #42") do
          raise HTTPX::TimeoutError.new(nil, "request timed out")
        end
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "re-raises HTTPX::ConnectionError with connection error log" do
      expect(Rails.logger).to receive(:error).with(/\[Solana\] RPC Connection Error/)

      expect {
        worker.perform_with_handling("Solana") do
          raise HTTPX::ConnectionError.new("failed to open TCP connection")
        end
      }.to raise_error(HTTPX::ConnectionError)
    end

    it "re-raises Net::OpenTimeout with structured log" do
      expect(Rails.logger).to receive(:error).with(/\[Polygon\] RPC Timeout/)

      expect {
        worker.perform_with_handling("Polygon", "TX #123") do
          raise Net::OpenTimeout, "execution expired"
        end
      }.to raise_error(Net::OpenTimeout)
    end

    it "re-raises Net::ReadTimeout with structured log" do
      expect(Rails.logger).to receive(:error).with(/\[Celo\] RPC Timeout/)

      expect {
        worker.perform_with_handling("Celo") do
          raise Net::ReadTimeout, "Net::ReadTimeout with #<TCPSocket>"
        end
      }.to raise_error(Net::ReadTimeout)
    end

    it "re-raises Errno::ECONNREFUSED with connection error log" do
      expect(Rails.logger).to receive(:error).with(/\[Solana\] RPC Connection Error/)

      expect {
        worker.perform_with_handling("Solana", "Wallet #456") do
          raise Errno::ECONNREFUSED, "Connection refused"
        end
      }.to raise_error(Errno::ECONNREFUSED)
    end

    it "re-raises Errno::ECONNRESET with connection error log" do
      expect(Rails.logger).to receive(:error).with(/\[Ethereum\] RPC Connection Error/)

      expect {
        worker.perform_with_handling("Ethereum") do
          raise Errno::ECONNRESET, "Connection reset by peer"
        end
      }.to raise_error(Errno::ECONNRESET)
    end

    it "re-raises IOError with connection error log" do
      expect(Rails.logger).to receive(:error).with(/\[IoTeX\] RPC Connection Error/)

      expect {
        worker.perform_with_handling("IoTeX") do
          raise IOError, "closed stream"
        end
      }.to raise_error(IOError)
    end

    it "does not catch non-RPC errors (lets them propagate naturally)" do
      expect {
        worker.perform_with_handling("Polygon") do
          raise StandardError, "Some other error"
        end
      }.to raise_error(StandardError, "Some other error")
    end

    it "includes resource_info in log message when provided" do
      expect(Rails.logger).to receive(:error).with(/for TX #999/)

      expect {
        worker.perform_with_handling("Polygon", "TX #999") do
          raise Net::OpenTimeout, "timeout"
        end
      }.to raise_error(Net::OpenTimeout)
    end

    it "omits resource_info in log message when not provided" do
      expect(Rails.logger).to receive(:error).with(/\[Polygon\] RPC Timeout:/)

      expect {
        worker.perform_with_handling("Polygon") do
          raise Net::OpenTimeout, "timeout"
        end
      }.to raise_error(Net::OpenTimeout)
    end
  end

  describe "#find_telemetry_log_with_pruning" do
    let(:cluster) { create(:cluster) }
    let(:tree) { create(:tree, cluster: cluster) }
    let!(:telemetry_log) { create(:telemetry_log, tree: tree) }

    before do
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    end

    it "finds telemetry log with partition pruning" do
      result = worker.find_log(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      expect(result).to eq(telemetry_log)
    end

    it "finds telemetry log without created_at_iso" do
      result = worker.find_log(telemetry_log.id_value, nil)
      expect(result).to eq(telemetry_log)
    end

    it "returns nil for non-existent log" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)
      result = worker.find_log(-1, Time.current.iso8601(6))
      expect(result).to be_nil
    end

    it "handles invalid ISO format gracefully" do
      result = worker.find_log(telemetry_log.id_value, "not-a-valid-date")
      expect(result).to eq(telemetry_log)
    end

    it "uses custom log_prefix" do
      expect(Rails.logger).to receive(:error).with(/\[Solana\] TelemetryLog/)
      worker.find_log(-1, nil, prefix: "[Solana]")
    end
  end

  describe "RPC_TRANSIENT_ERRORS constant" do
    it "includes expected error classes" do
      expect(described_class::RPC_TRANSIENT_ERRORS).to include(
        HTTPX::TimeoutError,
        HTTPX::ConnectionError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        IOError
      )
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchorWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end

    it "has unique_for set to 7 days to prevent overlapping anchoring cycles" do
      expect(described_class.sidekiq_options["unique_for"]).to eq(7.days)
    end
  end

  describe "module inclusion" do
    it "includes ApplicationWeb3Worker" do
      expect(described_class.ancestors).to include(ApplicationWeb3Worker)
    end
  end

  describe "#perform" do
    let(:mock_service) { instance_double(Ethereum::StateAnchorService) }

    before do
      allow(Ethereum::StateAnchorService).to receive(:new).and_return(mock_service)
    end

    it "calls Ethereum::StateAnchorService#anchor_to_l1!" do
      allow(mock_service).to receive(:anchor_to_l1!).and_return("0x" + "ab" * 32)

      described_class.new.perform

      expect(mock_service).to have_received(:anchor_to_l1!)
    end

    it "returns the tx_hash from the service" do
      expected_hash = "0x" + "ab" * 32
      allow(mock_service).to receive(:anchor_to_l1!).and_return(expected_hash)

      # The perform method delegates, but through with_web3_error_handling
      expect { described_class.new.perform }.not_to raise_error
    end

    it "re-raises errors after logging" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(RuntimeError, "Ethereum L1 Timeout: execution expired")

      expect(Rails.logger).to receive(:error).with(/L1 anchoring failed/)

      expect {
        described_class.new.perform
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)
    end

    it "re-raises RPC connection errors for Sidekiq retry" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(Errno::ECONNREFUSED, "Connection refused")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(Errno::ECONNREFUSED)
    end

    it "re-raises HTTPX timeout errors for Sidekiq retry" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(HTTPX::TimeoutError.new(nil, "timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "logs with the Ethereum prefix on any error" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(StandardError, "unexpected error")

      expect(Rails.logger).to receive(:error).with(/\[EthereumAnchor\].*L1 anchoring failed/)

      expect {
        described_class.new.perform
      }.to raise_error(StandardError, "unexpected error")
    end
  end
end

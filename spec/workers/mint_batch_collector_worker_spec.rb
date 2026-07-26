# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintBatchCollectorWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the web3 queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "uses lock: :until_executed for idempotency" do
      expect(described_class.sidekiq_options["lock"]).to eq(:until_executed)
    end
  end

  describe "module inclusion" do
    it "includes ApplicationWeb3Worker" do
      expect(described_class.ancestors).to include(ApplicationWeb3Worker)
    end
  end

  describe "#perform" do
    before do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
    end

    it "calls Treasury::MintBatchCollectorService" do
      described_class.new.perform
      expect(Treasury::MintBatchCollectorService).to have_received(:call)
    end

    it "delegates through with_web3_error_handling" do
      # The service is called within the web3 error handling block
      described_class.new.perform
      expect(Treasury::MintBatchCollectorService).to have_received(:call).once
    end

    it "re-raises errors after logging" do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
        .and_raise(RuntimeError, "RPC timeout")

      expect {
        described_class.new.perform
      }.to raise_error(RuntimeError, /RPC timeout/)
    end

    it "re-raises HTTPX::TimeoutError for Sidekiq retry" do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
        .and_raise(HTTPX::TimeoutError.new(nil, "Polygon RPC timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "re-raises connection errors for Sidekiq retry" do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
        .and_raise(Errno::ECONNREFUSED, "RPC node down")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end

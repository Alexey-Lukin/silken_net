# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintBatchCollectorWorker, type: :worker do
  describe "#perform" do
    before do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
    end

    it "calls Treasury::MintBatchCollectorService" do
      described_class.new.perform
      expect(Treasury::MintBatchCollectorService).to have_received(:call)
    end

    it "uses the web3 queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "re-raises errors after logging" do
      allow(Treasury::MintBatchCollectorService).to receive(:call)
        .and_raise(RuntimeError, "RPC timeout")

      expect {
        described_class.new.perform
      }.to raise_error(RuntimeError, /RPC timeout/)
    end
  end
end

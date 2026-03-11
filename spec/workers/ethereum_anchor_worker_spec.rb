# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchorWorker, type: :worker do
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

    it "uses the web3 queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "re-raises errors after logging" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(RuntimeError, "Ethereum L1 Timeout: execution expired")

      expect(Rails.logger).to receive(:error).with(/L1 anchoring failed/)

      expect {
        described_class.new.perform
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)
    end
  end
end

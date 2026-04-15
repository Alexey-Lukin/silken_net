# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreasuryMonitorWorker, type: :worker do
  describe "#perform" do
    let(:mock_results) do
      [
        { network: "polygon", status: :healthy, ratio: 20.0 },
        { network: "solana", status: :healthy, ratio: 20.0 },
        { network: "celo", status: :critical, ratio: 0.2 },
        { network: "ethereum", status: :error, ratio: 0.0 }
      ]
    end

    before do
      allow(Treasury::MonitorService).to receive(:call).and_return(mock_results)
    end

    it "calls Treasury::MonitorService" do
      described_class.new.perform
      expect(Treasury::MonitorService).to have_received(:call)
    end

    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "logs summary with counts" do
      expect(Rails.logger).to receive(:info).with(/2 healthy, 1 critical, 1 errors/)
      described_class.new.perform
    end
  end
end

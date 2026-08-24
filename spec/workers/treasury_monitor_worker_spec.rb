# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreasuryMonitorWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
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

    it "logs summary with counts" do
      allow(Rails.logger).to receive(:info).with(/2 healthy, 1 critical, 1 errors/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/2 healthy, 1 critical, 1 errors/)
    end

    it "logs correct counts when all healthy" do
      allow(Treasury::MonitorService).to receive(:call).and_return([
        { network: "polygon", status: :healthy, ratio: 20.0 },
        { network: "solana", status: :healthy, ratio: 15.0 }
      ])

      allow(Rails.logger).to receive(:info).with(/2 healthy, 0 critical, 0 errors/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/2 healthy, 0 critical, 0 errors/)
    end

    it "logs correct counts when all critical" do
      allow(Treasury::MonitorService).to receive(:call).and_return([
        { network: "polygon", status: :critical, ratio: 0.1 },
        { network: "celo", status: :critical, ratio: 0.01 }
      ])

      allow(Rails.logger).to receive(:info).with(/0 healthy, 2 critical, 0 errors/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/0 healthy, 2 critical, 0 errors/)
    end

    it "handles empty results from MonitorService" do
      allow(Treasury::MonitorService).to receive(:call).and_return([])

      allow(Rails.logger).to receive(:info).with(/0 healthy, 0 critical, 0 errors/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/0 healthy, 0 critical, 0 errors/)
    end

    it "re-raises HTTPX::TimeoutError for Sidekiq retry" do
      allow(Treasury::MonitorService).to receive(:call)
        .and_raise(HTTPX::TimeoutError.new(nil, "RPC timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "re-raises connection errors for Sidekiq retry" do
      allow(Treasury::MonitorService).to receive(:call)
        .and_raise(Errno::ECONNREFUSED, "RPC node unreachable")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end

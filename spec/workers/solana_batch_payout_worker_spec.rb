# frozen_string_literal: true

require "rails_helper"

RSpec.describe SolanaBatchPayoutWorker, type: :worker do
  describe "#perform" do
    it "delegates to Solana::BatchPayoutService" do
      allow(Solana::BatchPayoutService).to receive(:call)

      described_class.new.perform

      expect(Solana::BatchPayoutService).to have_received(:call)
    end

    it "re-raises CircuitOpenError so Sidekiq retries later" do
      allow_any_instance_of(described_class).to receive(:with_circuit_breaker)
        .and_raise(Web3CircuitBreaker::CircuitOpenError, "Circuit OPEN")

      expect { described_class.new.perform }
        .to raise_error(Web3CircuitBreaker::CircuitOpenError)
    end
  end

  describe "sidekiq options" do
    it "uses the web3 queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end
end

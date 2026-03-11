# frozen_string_literal: true

require "rails_helper"

RSpec.describe KlimaRetirementWorker, type: :worker do
  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }
  let(:wallet)       { tree.wallet }

  let(:mock_service) { instance_double(KlimaDao::RetirementService) }

  before do
    allow(KlimaDao::RetirementService).to receive(:new).and_return(mock_service)
    allow(mock_service).to receive(:retire_carbon!)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#perform" do
    it "calls KlimaDao::RetirementService with correct arguments" do
      described_class.new.perform(wallet.id, "100.0")

      expect(KlimaDao::RetirementService).to have_received(:new).with(wallet, BigDecimal("100.0"))
      expect(mock_service).to have_received(:retire_carbon!)
    end

    it "returns early when wallet is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)

      described_class.new.perform(-1, "100.0")

      expect(KlimaDao::RetirementService).not_to have_received(:new)
    end

    it "handles InsufficientBalanceError without re-raising" do
      allow(mock_service).to receive(:retire_carbon!)
        .and_raise(KlimaDao::RetirementService::InsufficientBalanceError, "Not enough funds")

      expect {
        described_class.new.perform(wallet.id, "100.0")
      }.not_to raise_error
    end

    it "handles InvalidTokenTypeError without re-raising" do
      allow(mock_service).to receive(:retire_carbon!)
        .and_raise(KlimaDao::RetirementService::InvalidTokenTypeError, "Wrong token")

      expect {
        described_class.new.perform(wallet.id, "100.0")
      }.not_to raise_error
    end

    it "re-raises unexpected errors for Sidekiq retry" do
      allow(mock_service).to receive(:retire_carbon!)
        .and_raise(StandardError, "RPC timeout")

      expect {
        described_class.new.perform(wallet.id, "100.0")
      }.to raise_error(StandardError, "RPC timeout")
    end

    it "uses web3 queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Celo::CommunityRewardService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:target_date) { Date.yesterday }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CELO_RPC_URL", anything).and_return("https://alfajores-forno.celo-testnet.org")
    allow(ENV).to receive(:fetch).with("ORACLE_PRIVATE_KEY").and_return("0x" + "ab" * 32)
    allow(ENV).to receive(:fetch).with("CELO_CUSD_CONTRACT_ADDRESS").and_return("0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1")

    # Kredis може бути відсутнім у тестовому середовищі
    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end
  end

  describe "#reward_community!" do
    context "when cluster is healthy and eligible" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.05,
          fraud_detected: false
        )
      end

      before do
        mock_client = instance_double(Eth::Client)
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Key).to receive(:new).and_return(instance_double(Eth::Key, address: "0x" + "aa" * 20))
        allow(Eth::Contract).to receive(:from_abi).and_return(double("Contract"))
        allow(mock_client).to receive(:transact).and_return("0x" + SecureRandom.hex(32))
        allow(Kredis).to receive(:lock).and_yield
      end

      it "creates a BlockchainTransaction with celo network and cusd token" do
        expect {
          described_class.new(cluster, target_date).reward_community!
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.blockchain_network).to eq("celo")
        expect(tx.token_type).to eq("cusd")
        expect(tx.amount).to eq(5.0)
        expect(tx.to_address).to eq(organization.crypto_public_address)
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to be_present
        expect(tx.cluster).to eq(cluster)
      end

      it "returns the tx_hash on success" do
        result = described_class.new(cluster, target_date).reward_community!
        expect(result).to start_with("0x")
      end

      it "logs the reward" do
        expect(Rails.logger).to receive(:info).with(/Celo ReFi.*Винагорода.*5\.0 cUSD/)
        described_class.new(cluster, target_date).reward_community!
      end

      it "uses Kredis.lock for nonce management" do
        expect(Kredis).to receive(:lock).and_yield
        described_class.new(cluster, target_date).reward_community!
      end
    end

    context "guard clause 1: no AiInsight for target_date" do
      it "returns nil without creating a transaction" do
        expect {
          result = described_class.new(cluster, target_date).reward_community!
          expect(result).to be_nil
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "guard clause 1: stress_index too high" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.5,
          fraud_detected: false
        )
      end

      it "returns nil without creating a transaction" do
        expect {
          result = described_class.new(cluster, target_date).reward_community!
          expect(result).to be_nil
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "guard clause 1: stress_index at boundary (0.2)" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.2,
          fraud_detected: false
        )
      end

      before do
        mock_client = instance_double(Eth::Client)
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Key).to receive(:new).and_return(instance_double(Eth::Key, address: "0x" + "aa" * 20))
        allow(Eth::Contract).to receive(:from_abi).and_return(double("Contract"))
        allow(mock_client).to receive(:transact).and_return("0x" + SecureRandom.hex(32))
        allow(Kredis).to receive(:lock).and_yield
      end

      it "is eligible (stress_index == 0.2 passes the guard)" do
        expect {
          described_class.new(cluster, target_date).reward_community!
        }.to change(BlockchainTransaction, :count).by(1)
      end
    end

    context "guard clause 1: fraud detected" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.05,
          fraud_detected: true
        )
      end

      it "returns nil without creating a transaction" do
        expect {
          result = described_class.new(cluster, target_date).reward_community!
          expect(result).to be_nil
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "guard clause 2: organization has no crypto address" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.05,
          fraud_detected: false
        )
      end

      before do
        # Bypass validation to simulate legacy data or missing address
        organization.update_column(:crypto_public_address, nil)
      end

      it "returns nil without creating a transaction" do
        expect {
          result = described_class.new(cluster, target_date).reward_community!
          expect(result).to be_nil
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "when Celo RPC fails" do
      let!(:insight) do
        create(:ai_insight,
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: target_date,
          stress_index: 0.05,
          fraud_detected: false
        )
      end

      before do
        mock_client = instance_double(Eth::Client)
        allow(Eth::Client).to receive(:create).and_return(mock_client)
        allow(Eth::Key).to receive(:new).and_return(instance_double(Eth::Key, address: "0x" + "aa" * 20))
        allow(Eth::Contract).to receive(:from_abi).and_return(double("Contract"))
        allow(mock_client).to receive(:transact).and_raise(StandardError, "Celo RPC timeout")
        allow(Kredis).to receive(:lock).and_yield
      end

      it "re-raises errors for Sidekiq retry" do
        expect {
          described_class.new(cluster, target_date).reward_community!
        }.to raise_error(StandardError, "Celo RPC timeout")
      end
    end
  end
end

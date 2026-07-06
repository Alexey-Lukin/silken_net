# frozen_string_literal: true

require "rails_helper"

RSpec.describe Insurance::ReserveGate do
  let(:cluster) { create(:cluster) }
  let(:insurance) do
    create(:parametric_insurance, cluster: cluster, payout_amount: 100_000, token_type: :carbon_coin)
  end

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "c" * 40
    ENV["DAO_TREASURY_ADDRESS"] ||= "0x" + "d" * 40
    Rails.cache.delete(BlockchainMintingService::TREASURY_BALANCE_CACHE_KEY)
    allow(SystemParameter).to receive(:current).and_call_original
  end

  def stub_thresholds(cap: 0, ratio: 0)
    allow(SystemParameter).to receive(:current)
      .with(:insurance_aggregate_payout_cap_scc, default: 0).and_return(cap)
    allow(SystemParameter).to receive(:current)
      .with(:insurance_reserve_adequacy_ratio, default: 0).and_return(ratio)
  end

  def stub_reserve(scc_balance)
    client = instance_double(Eth::Client)
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(client)
    allow(Eth::Contract).to receive(:from_abi).and_return(instance_double(Eth::Contract))
    allow(client).to receive(:call).and_return(scc_balance * (10**18))
  end

  # Внутрішня Internal-mint виплата (sourceable=ParametricInsurance, etherisc_policy_id NULL).
  def internal_payout(amount:, status: :confirmed, created_at: 1.hour.ago, etherisc: nil)
    src = create(:parametric_insurance, cluster: cluster, etherisc_policy_id: etherisc)
    create(:blockchain_transaction, sourceable: src, token_type: :carbon_coin,
                                    status: status, amount: amount, created_at: created_at)
  end

  describe ".call" do
    it "is inert (ok) when both thresholds are off (default 0)" do
      stub_thresholds(cap: 0, ratio: 0)

      result = described_class.call(insurance)

      expect(result).to be_ok
      expect(result.reason).to eq(:ok)
    end

    context "with the aggregate correlated-event cap armed" do
      before { stub_thresholds(cap: 500_000) }

      it "passes when 24h Internal-mint + payout is under the cap" do
        internal_payout(amount: 200_000) # 200k + 100k = 300k < 500k
        expect(described_class.call(insurance)).to be_ok
      end

      it "breaches when 24h Internal-mint + payout exceeds the cap" do
        internal_payout(amount: 450_000, status: :sent) # 450k + 100k = 550k > 500k
        result = described_class.call(insurance)
        expect(result).not_to be_ok
        expect(result.reason).to eq(:aggregate_cap)
      end

      it "excludes Etherisc-mode payouts (external USDC, not our emission)" do
        internal_payout(amount: 450_000, etherisc: "DIP-1") # excluded → only 100k payout
        expect(described_class.call(insurance)).to be_ok
      end

      it "excludes rows older than the 24h window (partition-prune bound)" do
        internal_payout(amount: 450_000, created_at: 25.hours.ago)
        expect(described_class.call(insurance)).to be_ok
      end

      it "counts unsettled (:pending/:manual_review) mints so concurrent payouts cannot slip past" do
        internal_payout(amount: 250_000, status: :pending)
        internal_payout(amount: 200_000, status: :manual_review) # 250k+200k+100k = 550k > 500k
        expect(described_class.call(insurance).reason).to eq(:aggregate_cap)
      end

      it "excludes the current payout's own :pending tx from the sum (no double-count)" do
        # The payout's own tx is committed :pending BEFORE the gate runs. At cap 150k, a 100k
        # payout double-counted (own row 100k + `+ payout` 100k = 200k) would falsely breach;
        # excluding current_tx_id leaves 0 + 100k = 100k < 150k → ok.
        own = create(:blockchain_transaction, sourceable: insurance, token_type: :carbon_coin,
                                              status: :pending, amount: 100_000, created_at: 1.minute.ago)
        allow(SystemParameter).to receive(:current)
          .with(:insurance_aggregate_payout_cap_scc, default: 0).and_return(150_000)

        expect(described_class.call(insurance, current_tx_id: own.id)).to be_ok
      end

      it "excludes :failed retry-remnants from the sum (OUTSTANDING_STATUSES = все крім failed)" do
        internal_payout(amount: 450_000, status: :failed) # :failed excluded → only 100k payout < 500k cap
        expect(described_class.call(insurance)).to be_ok
      end
    end

    context "with the reserve-adequacy ratio armed" do
      before { stub_thresholds(ratio: 2.0) }

      it "passes when outstanding ≤ reserve × ratio" do
        stub_reserve(100_000) # 100k × 2.0 = 200k ceiling; payout 100k ≤ 200k
        expect(described_class.call(insurance)).to be_ok
      end

      it "breaches when outstanding > reserve × ratio (unbacked inflation)" do
        stub_reserve(10_000) # 10k × 2.0 = 20k ceiling; payout 100k > 20k
        result = described_class.call(insurance)
        expect(result).not_to be_ok
        expect(result.reason).to eq(:reserve_inadequate)
      end
    end

    it "fails CLOSED when the reserve fetch errors (money-safety → hold, not unbacked mint)" do
      stub_thresholds(ratio: 2.0)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_raise(StandardError, "RPC down")

      result = described_class.call(insurance)

      expect(result).not_to be_ok
      expect(result.reason).to eq(:eval_error)
    end

    it "shares the treasury balance cache with minting (one RPC per 15-min window)" do
      stub_thresholds(ratio: 2.0)
      client = instance_double(Eth::Client)
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(client)
      allow(Eth::Contract).to receive(:from_abi).and_return(instance_double(Eth::Contract))
      allow(client).to receive(:call).and_return(100_000 * (10**18))

      described_class.call(insurance)
      described_class.call(insurance) # 2nd → warmed shared Web3::Erc20Reader cache

      expect(client).to have_received(:call).once
    end
  end
end

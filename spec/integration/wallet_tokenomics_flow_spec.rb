# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Wallet tokenomics flow end-to-end" do
  let(:organization) { create(:organization, crypto_public_address: "0x" + "ab" * 20) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(MintCarbonCoinWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_bulk)
    allow(AlertNotificationWorker).to receive(:perform_async)
  end

  describe "wallet credit and balance management" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "credits growth points to wallet" do
      wallet = tree.wallet
      expect(wallet.balance).to eq(0)

      wallet.credit!(100)
      expect(wallet.reload.balance).to eq(100)
    end

    it "tracks available balance with locked funds" do
      wallet = tree.wallet
      wallet.credit!(1000)

      wallet.lock_funds!(300)
      expect(wallet.available_balance).to eq(700)
      expect(wallet.locked_balance).to eq(300)
    end

    it "releases locked funds on failed transaction" do
      wallet = tree.wallet
      wallet.credit!(1000)
      wallet.lock_funds!(300)

      wallet.release_locked_funds!(300)
      expect(wallet.available_balance).to eq(1000)
      expect(wallet.locked_balance).to eq(0)
    end

    it "finalizes spend after blockchain confirmation" do
      wallet = tree.wallet
      wallet.credit!(1000)
      wallet.lock_funds!(500)

      wallet.finalize_spend!(500)
      expect(wallet.reload.balance).to eq(500)
      expect(wallet.locked_balance).to eq(0)
    end

    it "prevents double-spend via lock mechanism" do
      wallet = tree.wallet
      wallet.credit!(500)
      wallet.lock_funds!(400)

      expect { wallet.lock_funds!(200) }
        .to raise_error(RuntimeError, /Недостатньо доступних коштів/)
    end

    it "prevents finalize_spend! exceeding locked balance" do
      wallet = tree.wallet
      wallet.credit!(1000)
      wallet.lock_funds!(300)

      expect { wallet.finalize_spend!(500) }
        .to raise_error(RuntimeError, /locked_balance/)
    end
  end

  describe "lock_and_mint! flow" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates blockchain transaction and enqueues minting worker" do
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "cd" * 20)
      wallet.credit!(15_000)

      tx = wallet.lock_and_mint!(10_000, 10_000, :carbon_coin)
      expect(tx).to be_persisted
      expect(tx.amount).to eq(1)
      expect(tx.status).to eq("pending")
      expect(tx.locked_points).to eq(10_000)
      expect(wallet.reload.locked_balance).to eq(10_000)
      expect(MintCarbonCoinWorker).to have_received(:perform_async).with(tx.id)
    end

    it "falls back to organization crypto_public_address" do
      wallet = tree.wallet
      wallet.credit!(10_000)

      tx = wallet.lock_and_mint!(10_000, 10_000, :carbon_coin)
      expect(tx).to be_persisted
      expect(tx.to_address).to eq(organization.crypto_public_address)
    end

    it "raises error if tree is not active" do
      tree.update_column(:status, Tree.statuses[:dormant])
      wallet = tree.wallet
      wallet.credit!(10_000)

      expect { wallet.lock_and_mint!(10_000, 10_000) }
        .to raise_error(RuntimeError, /Дерево не активне/)
    end

    it "raises error if no crypto address available" do
      organization.update_column(:crypto_public_address, nil)
      wallet = tree.wallet
      wallet.update_column(:crypto_public_address, nil)
      wallet.credit!(10_000)

      expect { wallet.lock_and_mint!(10_000, 10_000) }
        .to raise_error(RuntimeError, /Відсутня крипто-адреса/)
    end
  end

  describe "TokenomicsEvaluatorWorker flow" do
    it "scans eligible wallets and initiates batch minting" do
      allow(BlockchainMintingService).to receive(:call_batch)

      tree1 = create(:tree, cluster: cluster, tree_family: tree_family)
      tree1.wallet.update!(crypto_public_address: "0x" + "aa" * 20)
      tree1.wallet.credit!(25_000)

      tree2 = create(:tree, cluster: cluster, tree_family: tree_family)
      tree2.wallet.update!(crypto_public_address: "0x" + "bb" * 20)
      tree2.wallet.credit!(5_000) # Below threshold

      TokenomicsEvaluatorWorker.new.perform

      # tree1 should have a pending blockchain transaction
      expect(tree1.wallet.blockchain_transactions.count).to eq(1)
      tx = tree1.wallet.blockchain_transactions.first
      expect(tx.status).to eq("pending")
      expect(tx.amount).to eq(2) # 25000 / 10000 = 2 tokens

      # tree2 should have no transactions (below threshold)
      expect(tree2.wallet.blockchain_transactions.count).to eq(0)

      expect(BlockchainMintingService).to have_received(:call_batch)
    end
  end

  describe "tree death triggers slashing protocol" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    it "initiates BurnCarbonTokensWorker when tree is marked deceased" do
      tree.update!(status: :deceased)

      expect(BurnCarbonTokensWorker).to have_received(:perform_bulk).with(
        [ [ organization.id, contract.id, tree.id ] ]
      )
    end

    it "does not initiate slashing for clusterless trees" do
      clusterless_tree = create(:tree, cluster: nil, tree_family: tree_family)
      clusterless_tree.update!(status: :deceased)

      # No cluster means no organization, no contracts to slash
      expect(BurnCarbonTokensWorker).not_to have_received(:perform_bulk)
    end
  end

  describe "NaasContract early termination" do
    let!(:contract) do
      create(:naas_contract,
             organization: organization,
             cluster: cluster,
             total_funding: 100_000,
             start_date: 60.days.ago,
             end_date: 300.days.from_now,
             cancellation_terms: {
               early_exit_fee_percent: 10,
               burn_accrued_points: true,
               min_days_before_exit: 30
             })
    end

    it "calculates early exit fee correctly" do
      fee = contract.calculate_early_exit_fee
      expect(fee).to eq(10_000.0) # 100,000 * 10%
    end

    it "calculates prorated refund" do
      refund = contract.calculate_prorated_refund
      expect(refund).to be > 0
      expect(refund).to be < contract.total_funding
    end

    it "terminates early and enqueues burning worker" do
      result = contract.terminate_early!

      expect(result[:refund]).to be > 0
      expect(result[:fee]).to eq(10_000.0)
      expect(result[:burned]).to be true
      expect(contract.reload.status).to eq("cancelled")
      expect(BurnCarbonTokensWorker).to have_received(:perform_async)
        .with(organization.id, contract.id)
    end

    it "prevents termination of non-active contract" do
      contract.update_column(:status, NaasContract.statuses[:fulfilled])

      expect { contract.terminate_early! }
        .to raise_error(RuntimeError, /Контракт не активний/)
    end
  end
end

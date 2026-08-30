# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Wallet tokenomics flow end-to-end" do
  let(:organization) { create(:organization, crypto_public_address: "0x" + "ab" * 20) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
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

    it "prevents double-spend via lock mechanism" do
      wallet = tree.wallet
      wallet.credit!(500)
      wallet.lock_funds!(400)

      expect { wallet.lock_funds!(200) }
        .to raise_error(RuntimeError, /Недостатньо доступних коштів/)
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
      tree1 = create(:tree, cluster: cluster, tree_family: tree_family)
      tree1.wallet.update!(crypto_public_address: "0x" + "aa" * 20)
      tree1.wallet.credit!(25_000)

      tree2 = create(:tree, cluster: cluster, tree_family: tree_family)
      tree2.wallet.update!(crypto_public_address: "0x" + "bb" * 20)
      tree2.wallet.credit!(5_000) # Below threshold

      # [SIDEKIQ PRO BATCH]: Orchestrator enqueues EvaluateTreeBatchWorker chunks
      TokenomicsEvaluatorWorker.new.perform

      # Drain the batch workers to simulate Sidekiq processing the batch
      EvaluateTreeBatchWorker.drain

      # tree1 should have a pending blockchain transaction
      expect(tree1.wallet.blockchain_transactions.count).to eq(1)
      tx = tree1.wallet.blockchain_transactions.first
      expect(tx.status).to eq("pending")
      expect(tx.amount).to eq(2) # 25000 / 10000 = 2 tokens

      # tree2 should have no transactions (below threshold)
      expect(tree2.wallet.blockchain_transactions.count).to eq(0)
    end

    # [ARCH.94] Сконвертовані бали лишаються в `locked_balance` НАЗАВЖДИ (04_01 §6 E.66),
    # тож наступний цикл мусить сайзитись від НЕсконвертованого залишку. Доти жоден
    # приклад не подавав у воркер гаманець із `locked_balance > 0` — саме тому
    # розходження «сайзинг від gross-balance ⊥ гард по available_balance» не мало
    # чим виявитись, і емісія тихо зупинялась після першого ж мінту.
    it "keeps minting on the second cycle after the first mint is confirmed" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      wallet = tree.wallet
      wallet.update!(crypto_public_address: "0x" + "cc" * 20)

      wallet.credit!(25_000)
      TokenomicsEvaluatorWorker.new.perform
      EvaluateTreeBatchWorker.drain

      first_tx = wallet.blockchain_transactions.sole
      first_tx.mark_as_sent!("0x" + "11" * 32)
      first_tx.confirm!(1_000, 21_000)

      expect(wallet.reload.locked_balance).to eq(20_000)

      wallet.credit!(25_000)
      # balance 50 000 · locked 20 000 → доступно 30 000 = рівно 3 токени
      TokenomicsEvaluatorWorker.new.perform
      EvaluateTreeBatchWorker.drain

      expect(wallet.blockchain_transactions.count).to eq(2)
      expect(wallet.blockchain_transactions.order(:id).last.amount).to eq(3)
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

    # [BIZ.22, ⚖️ 2026-08-30] Опція 1 MSA (§B.6.3): fee/refund зняті — термінація
    # це cancel + погоджена форфейтура, і результат не сміє нести грошових ключів.
    it "terminates early and enqueues burning worker without any refund/fee" do
      result = contract.terminate_early!

      expect(result).to eq({ burned: true })
      expect(contract.reload.status).to eq("cancelled")
      expect(BurnCarbonTokensWorker).to have_received(:perform_async)
        .with(organization.id, contract.id, nil, true)
    end

    it "prevents termination of non-active contract" do
      contract.update_column(:status, NaasContract.statuses[:fulfilled])

      expect { contract.terminate_early! }
        .to raise_error(RuntimeError, /Контракт не активний/)
    end
  end
end

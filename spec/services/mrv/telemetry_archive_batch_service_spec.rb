# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [E.60 Фаза 1б] Регресії BLOCKER'ів тріо-ревю: set-once атомарний bind ·
# create_or_find_by-конвергенція · батч-завжди (size-1 ≡ telemetry_merkle_root) ·
# windowless → zero32 БЕЗ рядка · build_failed NULL-root слід без біндингу.
RSpec.describe Mrv::TelemetryArchiveBatchService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) do
    w = tree.wallet
    w.update!(balance: 5000)
    allow(w.tree).to receive(:active?).and_return(true)
    w
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    silence_broadcasts!(:wallet_balance, :tree_map)
    TelemetryArchiveBatchWorker.clear
  end

  def windowed_tx!(points = 500)
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    wallet.reload.lock_and_mint!(points, 100)
  end

  def windowless_tx!
    wallet.blockchain_transactions.create!(
      amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
    )
  end

  describe "свіжа windowed-група" do
    it "створює батч, бінди всіх tx, root = union у глобальному порядку, первинний enqueue" do
      tx = windowed_tx!
      groups = described_class.group([ tx ], token_type: "carbon_coin", tax_rate: 0.02)

      expect(groups.size).to eq(1)
      batch = groups.first.batch
      expect(batch).to be_present
      expect(batch.archive_root).to eq(groups.first.root)
      expect(tx.reload.archive_batch_id).to eq(batch.id)
      expect(batch.leaf_count).to eq(1)
      expect(batch.tax_rate_applied).to eq(0.02)
      expect(TelemetryArchiveBatchWorker.jobs.size).to eq(1)
    end

    it "size-1 root бітово = telemetry_merkle_root (батч-завжди)" do
      tx = windowed_tx!
      groups = described_class.group([ tx ], token_type: "carbon_coin")
      expect(groups.first.root).to eq(tx.telemetry_merkle_root)
    end
  end

  describe "set-once membership" do
    it "повторний диспатч реюзає батч і root — другого рядка нема" do
      tx = windowed_tx!
      first = described_class.group([ tx ], token_type: "carbon_coin").first

      expect {
        second = described_class.group([ tx.reload ], token_type: "carbon_coin").first
        expect(second.root).to eq(first.root)
        expect(second.batch.id).to eq(first.batch.id)
      }.not_to change(TelemetryArchiveBatch, :count)
    end

    it "конвергує на існуючий рядок з тим самим root (RecordNotUnique ≠ zero32)" do
      tx = windowed_tx!
      expected_root = MerkleTree.root(
        Mrv::LineageWindow.logs_for(tx).map { |l| Mrv::TelemetryLeaf.cid_for(l) }
      )
      pre_existing = TelemetryArchiveBatch.create!(archive_root: expected_root, token_type: :carbon_coin)

      group = described_class.group([ tx ], token_type: "carbon_coin").first
      expect(group.root).to eq(expected_root)
      expect(group.batch.id).to eq(pre_existing.id)
      expect(tx.reload.archive_batch_id).to eq(pre_existing.id)
    end
  end

  describe "windowless-диспатч (insurance/celo/burn)" do
    it "дає ZERO_ROOT БЕЗ batch-row і без біндингу" do
      tx = windowless_tx!
      groups = nil
      expect {
        groups = described_class.group([ tx ], token_type: "carbon_coin")
      }.not_to change(TelemetryArchiveBatch, :count)

      expect(groups.first.root).to eq(described_class::ZERO_ROOT)
      expect(groups.first.batch).to be_nil
      expect(tx.reload.archive_batch_id).to be_nil
    end

    it "у змішаному слайсі windowless-tx стає членом звичайного батчу" do
      windowed = windowed_tx!
      windowless = windowless_tx!

      group = described_class.group([ windowed, windowless ], token_type: "carbon_coin").first
      expect(windowless.reload.archive_batch_id).to eq(group.batch.id)
      expect(group.batch.tx_count).to eq(2)
      expect(group.batch.leaf_count).to eq(1)
    end
  end

  describe "збій побудови (fail-open зі слідом + атомарність)" do
    it "rollback create+bind разом, лишає build_failed NULL-root слід БЕЗ біндингу, мінт іде zero32" do
      tx = windowed_tx!
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_raise("bind boom")

      group = described_class.group([ tx ], token_type: "carbon_coin").first

      expect(group.root).to eq(described_class::ZERO_ROOT)
      expect(group.batch).to be_nil
      expect(tx.reload.archive_batch_id).to be_nil
      # Атомарність: pending-рядка з root НЕМА (транзакція відкотила create).
      expect(TelemetryArchiveBatch.status_pending).to be_empty
      trace = TelemetryArchiveBatch.status_build_failed.sole
      expect(trace.archive_root).to be_nil
      expect(trace.tx_ids).to eq([ tx.id ])
      expect(trace.error_message).to include("bind boom")
      expect(TelemetryArchiveBatchWorker.jobs).to be_empty
    end
  end

  describe "bind-race (конкурент краде tx між читанням членства і bind'ом)" do
    it "відкочує partial-bind ЦІЛКОМ і ділить заново — жодного root'а, якого прив'язаний набір не відтворює" do
      tx1 = windowed_tx!
      tree2 = create(:tree, cluster: cluster)
      w2 = tree2.wallet
      w2.update!(balance: 5000)
      allow(w2.tree).to receive(:active?).and_return(true)
      create(:telemetry_log, tree: tree2, created_at: 90.minutes.ago)
      tx2 = w2.reload.lock_and_mint!(500, 100)

      thief = TelemetryArchiveBatch.create!(archive_root: "d" * 64, token_type: :carbon_coin)
      # Гонка = сервіс тримає STALE in-memory членство (nil), а конкурент уже
      # закомітив bind: крадемо через where-update_all (об'єкт tx2 не чіпається).
      BlockchainTransaction.where(id: tx2.id, created_at: tx2.created_at)
                           .update_all(archive_batch_id: thief.id)
      expect(tx2.archive_batch_id).to be_nil # in-memory досі stale

      groups = described_class.group([ tx1, tx2 ], token_type: "carbon_coin")

      expect(groups.size).to eq(2)
      thief_group = groups.find { |g| g.batch&.id == thief.id }
      expect(thief_group.txs).to eq([ tx2 ])
      own_group = groups.find { |g| g.batch && g.batch.id != thief.id }
      expect(own_group.txs).to eq([ tx1 ])
      expect(own_group.root).to eq(tx1.reload.telemetry_merkle_root)
      # Рядок із root'ом над union'ом ОБОХ вікон відкочено (leaf_count=2 не існує).
      expect(TelemetryArchiveBatch.where(leaf_count: 2)).to be_empty
    end
  end

  describe "подвійна bind-гонка (final_attempt fail-open)" do
    it "друга крадіжка поспіль → build_failed-слід + ZERO_ROOT, жодного чужого root'а" do
      tx = windowed_tx!
      thief = TelemetryArchiveBatch.create!(archive_root: "d" * 64, token_type: :carbon_coin)
      BlockchainTransaction.where(id: tx.id, created_at: tx.created_at)
                           .update_all(archive_batch_id: thief.id) # stale in-memory

      service = described_class.new([ tx ], token_type: "carbon_coin")
      group = service.send(:build_fresh_group, [ tx ], final_attempt: true)

      expect(group).not_to eq(:bind_race)
      expect(group.root).to eq(described_class::ZERO_ROOT)
      expect(group.batch).to be_nil
      trace = TelemetryArchiveBatch.status_build_failed.sole
      expect(trace.error_message).to include("bind-race двічі")
    end
  end

  describe "partition-pruning межі read-back'ів" do
    it "batch несе txs_created_from/to (обидва шляхи створення)" do
      tx = windowed_tx!
      batch = described_class.group([ tx ], token_type: "carbon_coin").first.batch
      expect(batch.txs_created_from).to be_within(1.second).of(tx.created_at)
      expect(batch.txs_created_to).to be_within(1.second).of(tx.created_at)

      # Другий шлях — build_failed-слід (`record_build_failure`): він несе ті самі
      # межі вікна. ⚠️ tx тут мусить бути WINDOWED, інакше збірка не доходить до
      # `update_all`, винятку немає й сліду не створюється ЗОВСІМ; і стаб ставиться
      # ПІСЛЯ створення, бо `lock_and_mint!` сам ходить через `update_all`.
      failed_tx = windowed_tx!
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_raise("boom")
      described_class.group([ failed_tx ], token_type: "carbon_coin")

      trace = TelemetryArchiveBatch.status_build_failed.sole
      expect(trace.txs_created_from).to be_within(1.second).of(failed_tx.created_at)
      expect(trace.txs_created_to).to be_within(1.second).of(failed_tx.created_at)
    end
  end

  describe "advisory dispatch-drift assert" do
    it "warn+метрика при size-1 розбіжності stored root, мінт НЕ блокується" do
      tx = windowed_tx!
      tx.update_column(:telemetry_merkle_root, "f" * 64)

      allow(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to receive(:increment).with(labels: { reason: "dispatch_drift" })

      group = described_class.group([ tx.reload ], token_type: "carbon_coin").first

      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to have_received(:increment).with(labels: { reason: "dispatch_drift" })
      expect(group.batch).to be_present
    end
  end
end

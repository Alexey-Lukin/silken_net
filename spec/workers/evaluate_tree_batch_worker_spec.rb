# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EvaluateTreeBatchWorker, type: :worker do
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "with eligible wallets above threshold" do
      it "creates blockchain transactions for wallets at or above threshold" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 25_000)

        expect {
          described_class.new.perform([ wallet.id ], "test-cycle")
        }.to change(BlockchainTransaction, :count).by(1)
      end

      it "locks the correct number of points into locked_balance" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 25_000)

        described_class.new.perform([ wallet.id ], "test-cycle")

        wallet.reload
        # 25000 / 10000 = 2 tokens, 20000 locked into locked_balance
        expect(wallet.locked_balance.to_i).to eq(20_000)
      end

      it "processes multiple wallets in a single chunk" do
        tree1 = create(:tree, status: :active)
        wallet1 = create(:wallet, tree: tree1, balance: 10_000)

        tree2 = create(:tree, status: :active)
        wallet2 = create(:wallet, tree: tree2, balance: 20_000)

        expect {
          described_class.new.perform([ wallet1.id, wallet2.id ], "test-cycle")
        }.to change(BlockchainTransaction, :count).by(2)
      end
    end

    context "with wallets below threshold" do
      it "skips wallets with balance below emission threshold" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 9_999)

        expect {
          described_class.new.perform([ wallet.id ], "test-cycle")
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "when error handling per wallet" do
      it "continues processing when one wallet fails" do
        tree1 = create(:tree, status: :active)
        wallet1 = create(:wallet, tree: tree1, balance: 10_000)

        tree2 = create(:tree, status: :active)
        wallet2 = create(:wallet, tree: tree2, balance: 20_000)

        # Перший гаманець кидає помилку
        call_count = 0
        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_wrap_original do |method, *args|
          call_count += 1
          raise "Lock error" if call_count == 1
          method.call(*args)
        end

        expect {
          described_class.new.perform([ wallet1.id, wallet2.id ], "test-cycle")
        }.to change(BlockchainTransaction, :count).by(1)
      end
    end

    context "when lock_and_mint! returns nil" do
      it "does not count nil transactions as minted" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 10_000)

        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_return(nil)

        expect {
          described_class.new.perform([ wallet.id ], "test-cycle")
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "with empty wallet_ids" do
      it "handles gracefully" do
        expect {
          described_class.new.perform([], "test-cycle")
        }.not_to raise_error
      end
    end

    context "with nonexistent wallet_ids" do
      it "handles gracefully" do
        expect {
          described_class.new.perform([ -1, -2 ], "test-cycle")
        }.not_to raise_error
      end
    end

    context "when wallet tree is nil" do
      it "logs error with empty DID and continues" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 10_000)
        allow_any_instance_of(Wallet).to receive(:tree).and_return(nil)
        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_raise(StandardError, "test error")

        allow(Rails.logger).to receive(:error).with(/Помилка вузла Tree /)

        described_class.new.perform([ wallet.id ], "test-cycle")

        expect(Rails.logger).to have_received(:error).with(/Помилка вузла Tree /)
      end
    end

    # [ARCH.94] Доти проковтнутий виняток жив ЛИШЕ в лог-рядку: джоба вертала
    # успіх, retry не було, DeadSet лишався порожній, mint-метрики не рухались
    # (tx не створено → гаманець не входив навіть у знаменник SLO). Саме так P1
    # грошового шляху прожив непоміченим — тепер він рухає власний лічильник.
    context "when a per-wallet mint fails" do
      it "increments the swallowed-error counter, so the failure is not silent" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 10_000)
        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_raise(StandardError, "boom")

        allow(SilkenNet::Metrics::MINT_CHUNK_ERRORS_TOTAL).to receive(:increment)

        described_class.new.perform([ wallet.id ], "test-cycle")

        expect(SilkenNet::Metrics::MINT_CHUNK_ERRORS_TOTAL).to have_received(:increment)
      end
    end
  end

  describe "sidekiq options" do
    it "uses default queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("default")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end

  describe "emission threshold (GOV.1 one-home)" do
    it "mints at the DAO-live threshold from TokenomicsEvaluatorWorker" do
      tree = create(:tree, status: :active)
      wallet = create(:wallet, tree: tree, balance: 6_000)
      allow(TokenomicsEvaluatorWorker).to receive(:emission_threshold).and_return(5_000)

      expect_any_instance_of(Wallet).to receive(:lock_and_mint!).with(5_000, 5_000)

      described_class.new.perform([ wallet.id ], "gov-cycle")
    end
  end
end

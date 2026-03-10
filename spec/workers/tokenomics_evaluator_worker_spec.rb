# frozen_string_literal: true

require "rails_helper"

RSpec.describe TokenomicsEvaluatorWorker, type: :worker do
  before do
    allow(BlockchainMintingService).to receive(:call_batch)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "with eligible wallets above threshold" do
      it "creates blockchain transactions for wallets at or above threshold" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 25_000)

        expect {
          described_class.new.perform
        }.to change(BlockchainTransaction, :count).by(1)
      end

      it "locks the correct number of points into locked_balance" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 25_000)

        described_class.new.perform

        wallet.reload
        # 25000 / 10000 = 2 tokens, 20000 locked into locked_balance
        expect(wallet.locked_balance.to_i).to eq(20_000)
      end

      it "calls BlockchainMintingService.call_batch" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 10_000)

        described_class.new.perform

        expect(BlockchainMintingService).to have_received(:call_batch)
      end
    end

    context "with wallets below threshold" do
      it "does not create transactions" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 9_999)

        expect {
          described_class.new.perform
        }.not_to change(BlockchainTransaction, :count)
      end

      it "does not call BlockchainMintingService" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 5_000)

        described_class.new.perform

        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end

    context "with inactive trees" do
      it "skips wallets of inactive trees" do
        tree = create(:tree, status: :removed)
        create(:wallet, tree: tree, balance: 50_000)

        expect {
          described_class.new.perform
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
          described_class.new.perform
        }.to change(BlockchainTransaction, :count).by(1)
      end
    end

    it "handles empty eligible wallets gracefully" do
      expect { described_class.new.perform }.not_to raise_error
    end

    context "when lock_and_mint! returns nil" do
      it "does not add nil transaction to created_tx_ids and skips batch minting" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 10_000)

        allow_any_instance_of(Wallet).to receive(:lock_and_mint!).and_return(nil)

        described_class.new.perform

        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end
  end
end

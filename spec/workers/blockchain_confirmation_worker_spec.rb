# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainConfirmationWorker, type: :worker do
  let(:wallet) { create(:wallet) }
  let(:tx_hash) { "0x" + SecureRandom.hex(32) }
  let!(:transaction) do
    create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent)
  end

  let(:client_double) { instance_double(Eth::Client) }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).with("ALCHEMY_POLYGON_RPC_URL").and_return(client_double)
  end

  describe "#perform" do
    context "when receipt confirms success (0x1)" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x1" } }
        )
      end

      it "confirms the blockchain transaction" do
        described_class.new.perform(tx_hash)

        transaction.reload
        expect(transaction.status).to eq("confirmed")
      end

      it "confirms all transactions with matching tx_hash" do
        tx2 = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent)

        described_class.new.perform(tx_hash)

        expect(transaction.reload.status).to eq("confirmed")
        expect(tx2.reload.status).to eq("confirmed")
      end

      # 🔴 [TEST.12 вісь ПРОВЕНАНСУ] Усі приклади вище кличуть `perform(tx_hash)` —
      # ОДНИМ аргументом, тоді як прод передає ДВА на кожному живому сайті
      # (`[ARCH.52] partition-prune`: sweeper · insurance-payout · обидва burning).
      # Тобто сюїта ходила формою, якої виробник не виробляє, і гілка з прунінгом
      # не виконувалась у `#perform` ЖОДНОГО разу. `.confirmation_scope` покритий
      # окремо й добре — але це інша ланка: доказу, що `perform` ПЕРЕДАЄ свій
      # другий аргумент далі, не було, і зняття його з виклику лишало сюїту
      # зеленою (виміряно мутацією), тобто прунінг тихо ставав повним скана́ми.
      it "передає ключ прунінгу далі: рядок поза вікном не чіпається" do
        out_of_window = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash,
                                                        status: :sent, created_at: 3.hours.ago)

        described_class.new.perform(tx_hash, transaction.created_at.iso8601)

        expect(transaction.reload.status).to eq("confirmed")
        expect(out_of_window.reload.status).to eq("sent")
      end

      it "parses hex blockNumber and gasUsed when the receipt includes them" do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x1", "blockNumber" => "0x10", "gasUsed" => "0x5208" } }
        )

        described_class.new.perform(tx_hash)

        transaction.reload
        expect(transaction.status).to eq("confirmed")
        expect(transaction.block_number).to eq(16)
        expect(transaction.gas_used).to eq(21_000)
      end
    end

    context "when receipt shows revert" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x0" } }
        )
      end

      it "fails the transaction with EVM revert reason" do
        described_class.new.perform(tx_hash)

        transaction.reload
        expect(transaction.status).to eq("failed")
        expect(transaction.error_message).to include("EVM Revert")
      end
    end

    context "when receipt is not yet available" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(nil)
      end

      it "raises to trigger Sidekiq retry (polling)" do
        expect { described_class.new.perform(tx_hash) }.to raise_error(RuntimeError, /Очікування підтвердження/)
      end
    end

    context "when receipt exists but result is nil" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return({})
      end

      it "raises to trigger Sidekiq retry" do
        expect { described_class.new.perform(tx_hash) }.to raise_error(RuntimeError, /Очікування підтвердження/)
      end
    end

    context "when tx_hash has no matching transactions" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x1" } }
        )
      end

      it "returns early for unknown hash" do
        transaction.destroy!

        # Should not raise
        expect { described_class.new.perform(tx_hash) }.not_to raise_error
      end
    end
  end

  describe "sidekiq_retries_exhausted" do
    let(:msg) { { "args" => [ tx_hash ] } }

    context "when sent transactions exist for the tx_hash" do
      it "delegates to MintingRollbackService" do
        allow(MintingRollbackService).to receive(:call) do |transactions:|
          expect(transactions.map(&:id)).to include(transaction.id)
        end

        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("timeout"))

        expect(MintingRollbackService).to have_received(:call)
      end
    end

    context "when no sent transactions exist (already resolved)" do
      before { transaction.update_column(:status, "confirmed") }

      it "logs warning and does not call MintingRollbackService" do
        allow(MintingRollbackService).to receive(:call)

        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("timeout"))

        expect(MintingRollbackService).not_to have_received(:call)
      end
    end

    context "when tx_hash is nil" do
      let(:msg) { { "args" => [ nil ] } }

      it "does nothing gracefully" do
        allow(MintingRollbackService).to receive(:call)

        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("timeout"))

        expect(MintingRollbackService).not_to have_received(:call)
      end
    end
  end

  describe ".confirmation_scope [ARCH.52 partition-prune]" do
    it "lower-bounds the lookup (excludes an OLDER same-hash tx before earliest−1h)" do
      out_of_window = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent, created_at: 3.hours.ago)
      scope = described_class.confirmation_scope(tx_hash, transaction.created_at.iso8601)

      expect(scope).to include(transaction)
      expect(scope).not_to include(out_of_window) # старіший за earliest−1h → не сканується
    end

    # [ARCH.52] LOWER-bound, НЕ symmetric ±1h: batch ділить 1 tx_hash на рядки з РІЗНИМИ
    # created_at; enqueue keys off earliest.iso8601 (reset-to-pending тримає старий created_at),
    # тож sibling НОВІШИЙ за earliest+1h МУСИТЬ лишатись у scope. Регресія
    # `created_at >= t−1h` → `BETWEEN t−1h AND t+1h` пройшла б попередній тест зеленою (old-row
    # і так виключений), але виштовхнула б цей newer-sibling → stuck :sent = locked funds.
    it "INCLUDES a newer same-hash sibling >1h after earliest (lower-bound, not symmetric)" do
      newer_sibling = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent, created_at: transaction.created_at + 2.hours)
      scope = described_class.confirmation_scope(tx_hash, transaction.created_at.iso8601)

      expect(scope).to include(transaction, newer_sibling)
    end

    it "falls back to unscoped tx_hash lookup when created_at_iso is nil (legacy/puro enqueue)" do
      out = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent, created_at: 3.hours.ago)

      expect(described_class.confirmation_scope(tx_hash, nil)).to include(transaction, out)
    end

    it "is resilient to a malformed created_at_iso (falls back, still finds the tx)" do
      expect(described_class.confirmation_scope(tx_hash, "not-a-date")).to include(transaction)
    end
  end
end

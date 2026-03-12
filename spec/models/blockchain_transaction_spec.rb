# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransaction, type: :model do
  describe "validations" do
    it "requires amount to be present and positive" do
      tx = build(:blockchain_transaction, amount: nil)
      expect(tx).not_to be_valid
      expect(tx.errors[:amount]).to be_present
    end

    it "rejects zero amount" do
      tx = build(:blockchain_transaction, amount: 0)
      expect(tx).not_to be_valid
    end

    it "requires a valid 0x address" do
      tx = build(:blockchain_transaction, to_address: "invalid")
      expect(tx).not_to be_valid
      expect(tx.errors[:to_address]).to be_present
    end

    it "requires tx_hash when status is sent" do
      tx = build(:blockchain_transaction, status: :sent, tx_hash: nil)
      expect(tx).not_to be_valid
      expect(tx.errors[:tx_hash]).to be_present
    end

    it "requires tx_hash when status is confirmed" do
      tx = build(:blockchain_transaction, status: :confirmed, tx_hash: nil)
      expect(tx).not_to be_valid
    end

    it "allows nil gas_price" do
      tx = build(:blockchain_transaction, gas_price: nil)
      expect(tx).to be_valid
    end

    it "rejects negative gas_price" do
      tx = build(:blockchain_transaction, gas_price: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:gas_price]).to be_present
    end

    it "rejects negative gas_used" do
      tx = build(:blockchain_transaction, gas_used: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:gas_used]).to be_present
    end

    it "rejects zero block_number" do
      tx = build(:blockchain_transaction, block_number: 0)
      expect(tx).not_to be_valid
      expect(tx.errors[:block_number]).to be_present
    end

    it "allows positive block_number" do
      tx = build(:blockchain_transaction, block_number: 12_345_678)
      expect(tx).to be_valid
    end

    it "rejects negative nonce" do
      tx = build(:blockchain_transaction, nonce: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:nonce]).to be_present
    end

    it "allows zero nonce (first transaction)" do
      tx = build(:blockchain_transaction, nonce: 0)
      expect(tx).to be_valid
    end
  end

  describe "#mark_as_sent!" do
    it "sets tx_hash, status, and sent_at" do
      tx = create(:blockchain_transaction, status: :processing, tx_hash: nil)
      hash = "0x" + SecureRandom.hex(32)

      freeze_time do
        tx.mark_as_sent!(hash)
        tx.reload

        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(hash)
        expect(tx.sent_at).to be_within(1.second).of(Time.current)
        expect(tx.error_message).to be_nil
      end
    end
  end

  describe "#confirm!" do
    it "sets confirmed status and confirmed_at timestamp" do
      tx = create(:blockchain_transaction, status: :sent)

      freeze_time do
        tx.confirm!
        tx.reload

        expect(tx.status).to eq("confirmed")
        expect(tx.confirmed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "accepts block_number for reorg protection" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!(54_321_000)
      tx.reload

      expect(tx.block_number).to eq(54_321_000)
    end

    it "accepts gas_cost for financial reporting" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!(54_321_000, 21_000)
      tx.reload

      expect(tx.block_number).to eq(54_321_000)
      expect(tx.gas_used).to eq(21_000)
    end

    it "works without arguments (backward compatible)" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!
      tx.reload

      expect(tx.status).to eq("confirmed")
      expect(tx.block_number).to be_nil
      expect(tx.gas_used).to be_nil
    end
  end

  describe "#fail!" do
    it "sets failed status and error message" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.fail!("RPC timeout")
      tx.reload

      expect(tx.status).to eq("failed")
      expect(tx.error_message).to eq("RPC timeout")
    end

    it "truncates long error messages to 500 characters" do
      tx = create(:blockchain_transaction, status: :sent)
      long_message = "x" * 1000
      tx.fail!(long_message)
      tx.reload

      expect(tx.error_message.length).to be <= 500
    end
  end

  describe "#explorer_url" do
    it "returns polygonscan URL when tx_hash is present" do
      tx = build(:blockchain_transaction, tx_hash: "0xabc123")
      expect(tx.explorer_url).to eq("https://polygonscan.com/tx/0xabc123")
    end

    it "returns nil when tx_hash is absent" do
      tx = build(:blockchain_transaction, tx_hash: nil, status: :pending)
      expect(tx.explorer_url).to be_nil
    end
  end

  describe "#polygonscan_url" do
    it "is an alias for explorer_url" do
      tx = build(:blockchain_transaction, tx_hash: "0xdef456")
      expect(tx.polygonscan_url).to eq(tx.explorer_url)
    end
  end

  describe "multichain support" do
    it "defaults blockchain_network to evm" do
      tx = create(:blockchain_transaction)
      expect(tx.blockchain_network).to eq("evm")
    end

    it "validates blockchain_network inclusion" do
      tx = build(:blockchain_transaction)
      tx.blockchain_network = "invalid_chain"
      expect(tx).not_to be_valid
      expect(tx.errors[:blockchain_network]).to be_present
    end

    it "accepts solana as blockchain_network" do
      tx = build(:blockchain_transaction,
        blockchain_network: "solana",
        to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV"
      )
      expect(tx).to be_valid
    end

    describe "#solana_network?" do
      it "returns true for solana transactions" do
        tx = build(:blockchain_transaction, blockchain_network: "solana",
                   to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")
        expect(tx.solana_network?).to be true
      end

      it "returns false for evm transactions" do
        tx = build(:blockchain_transaction, blockchain_network: "evm")
        expect(tx.solana_network?).to be false
      end
    end

    describe "#explorer_url for solana" do
      it "returns Solana Explorer URL for solana transactions" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV",
          tx_hash: "solana:sim:abc123"
        )
        expect(tx.explorer_url).to eq("https://explorer.solana.com/tx/solana:sim:abc123?cluster=devnet")
      end

      it "returns Polygonscan URL for evm transactions" do
        tx = build(:blockchain_transaction, tx_hash: "0xabc123", blockchain_network: "evm")
        expect(tx.explorer_url).to eq("https://polygonscan.com/tx/0xabc123")
      end
    end

    describe "Solana address validation" do
      it "validates Base58 format for solana network" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "invalid!address"
        )
        expect(tx).not_to be_valid
        expect(tx.errors[:to_address]).to be_present
      end

      it "rejects EVM address format for solana network" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "0x1234567890abcdef1234567890abcdef12345678"
        )
        expect(tx).not_to be_valid
      end
    end

    describe "#explorer_url for celo" do
      it "returns Celo Explorer URL for celo transactions" do
        tx = build(:blockchain_transaction,
          blockchain_network: "celo",
          to_address: "0x" + "a" * 40,
          tx_hash: "0xcelo123"
        )
        expect(tx.explorer_url).to eq("https://explorer.celo.org/alfajores/tx/0xcelo123")
      end
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:tx) { create(:blockchain_transaction, status: :pending, tx_hash: nil) }

    describe "initial state" do
      it "starts as pending" do
        expect(build(:blockchain_transaction, status: :pending)).to be_pending
      end
    end

    describe "#process!" do
      it "transitions from pending to processing" do
        tx.process!
        expect(tx.reload).to be_processing
      end

      it "rejects transition from confirmed" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.process! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#mark_as_sent!" do
      it "transitions from pending to sent and sets tx_hash + sent_at" do
        freeze_time do
          tx.mark_as_sent!("0xabc123")
          tx.reload
          expect(tx).to be_sent
          expect(tx.tx_hash).to eq("0xabc123")
          expect(tx.sent_at).to be_within(1.second).of(Time.current)
          expect(tx.error_message).to be_nil
        end
      end

      it "transitions from processing to sent" do
        tx.update_columns(status: described_class.statuses[:processing])
        tx.reload
        tx.mark_as_sent!("0xdef456")
        expect(tx.reload).to be_sent
      end

      it "rejects transition from confirmed" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.mark_as_sent!("0x1") }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#confirm!" do
      it "transitions from sent to confirmed and sets block_number + gas_used" do
        sent_tx = create(:blockchain_transaction, status: :sent)
        freeze_time do
          sent_tx.confirm!(42_000, 21_000)
          sent_tx.reload
          expect(sent_tx).to be_confirmed
          expect(sent_tx.block_number).to eq(42_000)
          expect(sent_tx.gas_used).to eq(21_000)
          expect(sent_tx.confirmed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "works without arguments (BlockchainConfirmationWorker pattern)" do
        sent_tx = create(:blockchain_transaction, status: :sent)
        sent_tx.confirm!
        expect(sent_tx.reload).to be_confirmed
      end

      it "rejects transition from pending" do
        expect { tx.confirm! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#fail!" do
      it "transitions from any state to failed and sets error_message" do
        allow(Rails.logger).to receive(:error)
        tx.fail!("EVM revert")
        tx.reload
        expect(tx).to be_failed
        expect(tx.error_message).to eq("EVM revert")
      end

      it "truncates long error messages to 500 chars" do
        allow(Rails.logger).to receive(:error)
        long_reason = "x" * 600
        tx.fail!(long_reason)
        expect(tx.reload.error_message.length).to be <= 500
      end

      it "can fail from sent state" do
        allow(Rails.logger).to receive(:error)
        sent_tx = create(:blockchain_transaction, status: :sent)
        sent_tx.fail!("timeout")
        expect(sent_tx.reload).to be_failed
      end

      it "logs the failure" do
        expect(Rails.logger).to receive(:error).with(/провалилася/)
        tx.fail!("revert")
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions" do
        expect(tx.may_process?).to be true
        expect(tx.may_mark_as_sent?).to be true
        expect(tx.may_confirm?).to be false
        expect(tx.may_fail?).to be true
      end
    end
  end
end

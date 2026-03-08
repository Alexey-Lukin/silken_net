# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  before do
    allow_any_instance_of(described_class).to receive(:broadcast_balance_update)
  end

  describe "#credit!" do
    it "atomically increments balance" do
      wallet = create(:tree).wallet
      original_balance = wallet.balance

      wallet.credit!(100)
      wallet.reload

      expect(wallet.balance).to eq(original_balance + 100)
    end

    it "does not change balance with zero points" do
      wallet = create(:tree).wallet
      original_balance = wallet.balance

      wallet.credit!(0)
      wallet.reload

      expect(wallet.balance).to eq(original_balance)
    end

    describe "broadcast throttling" do
      it "broadcasts on the first credit! call" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).once

        wallet.credit!(10)
      end

      it "throttles subsequent broadcasts within the throttle window" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).once

        3.times { wallet.credit!(10) }
      end

      it "broadcasts again after the throttle period expires" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).twice

        wallet.credit!(10)
        # Очищаємо кеш троттлінгу, імітуючи закінчення таймера
        Rails.cache.delete("wallet_broadcast_throttle:#{wallet.id}")
        wallet.credit!(10)
      end
    end
  end

  describe "#lock_and_mint!" do
    it "locks balance using locked_balance instead of immediate decrement" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000)
      allow(wallet.tree).to receive(:active?).and_return(true)
      allow(MintCarbonCoinWorker).to receive(:perform_async)

      wallet.lock_and_mint!(500, 100)
      wallet.reload

      expect(wallet.balance).to eq(1000)
      expect(wallet.locked_balance).to eq(500)
      expect(wallet.available_balance).to eq(500)
    end
  end

  describe "validations" do
    it "rejects negative balance" do
      wallet = create(:tree).wallet
      wallet.balance = -1

      expect(wallet).not_to be_valid
      expect(wallet.errors[:balance]).to include("must be greater than or equal to 0")
    end
  end

  describe "#available_balance" do
    it "returns balance minus locked_balance" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 500, locked_balance: 200)

      expect(wallet.available_balance).to eq(300)
    end
  end

  describe "#lock_funds!" do
    it "increments locked_balance by the given amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000)

      wallet.lock_funds!(400)
      wallet.reload

      expect(wallet.locked_balance).to eq(400)
      expect(wallet.available_balance).to eq(600)
    end

    it "raises when insufficient available balance" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 100, locked_balance: 50)

      expect { wallet.lock_funds!(100) }.to raise_error(RuntimeError, /Недостатньо доступних коштів/)
    end
  end

  describe "#release_locked_funds!" do
    it "decrements locked_balance by the given amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 400)

      wallet.release_locked_funds!(200)
      wallet.reload

      expect(wallet.locked_balance).to eq(200)
    end

    it "raises when releasing more than locked" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 100)

      expect { wallet.release_locked_funds!(200) }.to raise_error(RuntimeError, /розблокувати більше/)
    end
  end

  describe "#finalize_spend!" do
    it "decreases both balance and locked_balance" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 500)

      wallet.finalize_spend!(300)
      wallet.reload

      expect(wallet.balance).to eq(700)
      expect(wallet.locked_balance).to eq(200)
    end

    it "raises when locked_balance is less than amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 100)

      expect { wallet.finalize_spend!(200) }.to raise_error(RuntimeError, /locked_balance/)
    end

    it "raises when balance is less than amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 100, locked_balance: 200)

      expect { wallet.finalize_spend!(200) }.to raise_error(RuntimeError, /balance/)
    end
  end

  describe "locked_balance validation" do
    it "rejects negative locked_balance" do
      wallet = create(:tree).wallet
      wallet.locked_balance = -1

      expect(wallet).not_to be_valid
      expect(wallet.errors[:locked_balance]).to include("must be greater than or equal to 0")
    end
  end
end

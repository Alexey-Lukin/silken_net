# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
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
    it "atomically decrements balance using decrement!" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000)
      allow(wallet.tree).to receive(:active?).and_return(true)
      allow(MintCarbonCoinWorker).to receive(:perform_async)

      wallet.lock_and_mint!(500, 100)
      wallet.reload

      expect(wallet.balance).to eq(500)
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
end

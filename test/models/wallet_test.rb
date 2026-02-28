require "test_helper"

class WalletTest < ActiveSupport::TestCase
  test "credit! atomically increments balance" do
    wallet = wallets(:pine_wallet)
    original_balance = wallet.balance
    wallet.credit!(100)
    wallet.reload
    assert_equal original_balance + 100, wallet.balance
  end

  test "balance cannot be negative" do
    wallet = wallets(:pine_wallet)
    wallet.balance = -1
    refute wallet.valid?
    assert_includes wallet.errors[:balance], "must be greater than or equal to 0"
  end

  test "credit! with zero points does not change balance" do
    wallet = wallets(:pine_wallet)
    original_balance = wallet.balance
    wallet.credit!(0)
    wallet.reload
    assert_equal original_balance, wallet.balance
  end
end

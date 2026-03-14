# frozen_string_literal: true

# @label Wallet Balance Display
# @display bg_color "#000"
class WalletBalanceDisplayPreview < Lookbook::Preview
  # @label Tree Wallet (High Balance)
  # @notes Displays a soldier's wallet with significant SCC balance.
  def tree_wallet
    wallet = mock_wallet(balance: 12_847.123456, locked: 500.0, esg: 200.0, owner_did: "SNET-00000042")
    render Wallets::BalanceDisplay.new(wallet: wallet)
  end

  # @label Low Balance with Locked Funds
  # @notes Shows a wallet where most funds are locked for pending minting.
  def locked_funds
    wallet = mock_wallet(balance: 100.0, locked: 85.0, esg: 0.0, owner_did: "SNET-00000099")
    render Wallets::BalanceDisplay.new(wallet: wallet)
  end

  # @label Organization Wallet
  # @notes Displays an organization's treasury wallet.
  def organization_wallet
    wallet = mock_wallet(balance: 250_000.50, locked: 10_000.0, esg: 50_000.0, owner_org: "EcoFuture Fund")
    render Wallets::BalanceDisplay.new(wallet: wallet)
  end

  # @label Zero Balance
  # @notes Fresh wallet with no tokens minted yet.
  def zero_balance
    wallet = mock_wallet(balance: 0.0, locked: 0.0, esg: 0.0, owner_did: "SNET-00000001")
    render Wallets::BalanceDisplay.new(wallet: wallet)
  end

  # @label Interactive
  # @param balance text "Total SCC balance"
  # @param locked_balance text "Locked for pending transactions"
  # @param esg_retired text "ESG retired balance"
  def interactive(balance: "5000.0", locked_balance: "250.0", esg_retired: "100.0")
    wallet = mock_wallet(
      balance: balance.to_f,
      locked: locked_balance.to_f,
      esg: esg_retired.to_f,
      owner_did: "SNET-PREVIEW"
    )
    render Wallets::BalanceDisplay.new(wallet: wallet)
  end

  private

  def mock_wallet(balance:, locked:, esg:, owner_did: nil, owner_org: nil)
    tree = owner_did ? OpenStruct.new(did: owner_did) : nil
    org = owner_org ? OpenStruct.new(name: owner_org) : nil

    OpenStruct.new(
      id: 1,
      scc_balance: balance,
      balance: balance,
      locked_balance: locked,
      esg_retired_balance: esg,
      available_balance: balance - locked,
      tree: tree,
      organization: org
    )
  end
end

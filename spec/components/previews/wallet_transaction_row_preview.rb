# frozen_string_literal: true

# @label Wallet Transaction Row
# @display bg_color "#000"
class WalletTransactionRowPreview < Lookbook::Preview
  # @label Confirmed Carbon Coin
  # @notes A confirmed SCC minting transaction with on-chain hash.
  def confirmed_carbon
    tx = mock_tx(token_type: "carbon_coin", status: "confirmed", amount: 10, tx_hash: "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
    render_in_table { render Wallets::TransactionRow.new(tx: tx) }
  end

  # @label Pending Forest Coin
  # @notes A pending SFC transaction without a block hash yet.
  def pending_forest
    tx = mock_tx(token_type: "forest_coin", status: "pending", amount: 5, tx_hash: nil)
    render_in_table { render Wallets::TransactionRow.new(tx: tx) }
  end

  # @label Failed Transaction
  # @notes A failed transaction displayed with red status indicator.
  def failed
    tx = mock_tx(token_type: "carbon_coin", status: "failed", amount: 25, tx_hash: "0xdead0000000000000000000000000000000000000000000000000000deadbeef")
    render_in_table { render Wallets::TransactionRow.new(tx: tx) }
  end

  # @label Processing (Sent)
  # @notes A transaction currently in the mempool, awaiting confirmation.
  def processing
    tx = mock_tx(token_type: "carbon_coin", status: "sent", amount: 100, tx_hash: "0x7777888899990000aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666")
    render_in_table { render Wallets::TransactionRow.new(tx: tx) }
  end

  # @label Interactive
  # @param token_type select { choices: [carbon_coin, forest_coin, cusd] }
  # @param status select { choices: [pending, processing, sent, confirmed, failed] }
  # @param amount text
  def interactive(token_type: "carbon_coin", status: "confirmed", amount: "42")
    tx = mock_tx(token_type: token_type, status: status, amount: amount.to_f, tx_hash: status == "pending" ? nil : "0xaabbccdd11223344556677889900aabbccdd11223344556677889900aabbccdd")
    render_in_table { render Wallets::TransactionRow.new(tx: tx) }
  end

  private

  def mock_tx(token_type:, status:, amount:, tx_hash:)
    OpenStruct.new(
      id: 1,
      token_type: token_type,
      status: status,
      amount: amount,
      tx_hash: tx_hash,
      blockchain_network: "evm",
      explorer_url: tx_hash ? "https://polygonscan.com/tx/#{tx_hash}" : nil,
      created_at: 2.hours.ago
    )
  end

  def render_in_table(&block)
    render_with_template(locals: { content: capture(&block) }, template: "wallet_transaction_row_preview/wrapper")
  end
end

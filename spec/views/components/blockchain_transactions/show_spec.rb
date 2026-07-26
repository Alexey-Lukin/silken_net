# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::Show do
  let(:transaction) { mock_transaction }
  let(:html) { render_component(transaction: transaction) }

  def mock_transaction(id: 1, amount: "0.005", status: "confirmed", token_type: "carbon_coin",
                       tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                       explorer_url: "https://polygonscan.com/tx/0xabc",
                       blockchain_network: "polygon", locked_points: 10_000,
                       to_address: "0x1234567890abcdef1234567890abcdef12345678",
                       gas_price: 30, gas_used: 21_000, block_number: 123_456,
                       nonce: 42, sent_at: 1.hour.ago, confirmed_at: 30.minutes.ago,
                       notes: nil, error_message: nil,
                       wallet_tree_did: "SNET-00000042", wallet_balance: 12.5,
                       has_wallet: true)
    tree = OpenStruct.new(did: wallet_tree_did)
    wallet = has_wallet ? OpenStruct.new(tree: tree, balance: wallet_balance) : nil

    tx = OpenStruct.new(
      id: id,
      amount: amount,
      status: status,
      token_type: token_type,
      tx_hash: tx_hash,
      explorer_url: explorer_url,
      blockchain_network: blockchain_network,
      locked_points: locked_points,
      to_address: to_address,
      gas_price: gas_price,
      gas_used: gas_used,
      block_number: block_number,
      nonce: nonce,
      sent_at: sent_at,
      confirmed_at: confirmed_at,
      created_at: 2.hours.ago,
      updated_at: 30.minutes.ago,
      notes: notes,
      error_message: error_message,
      wallet: wallet
    )
    tx.define_singleton_method(:model_name) { ActiveModel::Name.new(BlockchainTransaction) }
    tx.define_singleton_method(:to_key) { [ id ] }
    tx.define_singleton_method(:to_param) { id.to_s }
    tx.define_singleton_method(:solana_network?) { blockchain_network == "solana" }
    tx.define_singleton_method(:celo_network?) { blockchain_network == "celo" }
    tx
  end

  describe "header" do
    it "displays amount with SCC label" do
      expect(html).to include("0.005 SCC")
    end

    it "displays transaction ID" do
      expect(html).to include("#1")
    end

    it "displays Transaction Record label" do
      expect(html).to include("Transaction Record")
    end
  end

  describe "status badge" do
    it "renders confirmed with emerald style" do
      expect(html).to include("confirmed")
      expect(html).to include("bg-emerald-900")
    end

    it "renders processing with warning style" do
      tx = mock_transaction(status: "processing")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("processing")
      expect(rendered).to include("bg-status-warning")
    end

    it "renders sent with warning style" do
      tx = mock_transaction(status: "sent")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("sent")
      expect(rendered).to include("bg-status-warning")
    end

    it "renders pending with zinc style" do
      tx = mock_transaction(status: "pending")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("pending")
      expect(rendered).to include("bg-zinc-800")
    end

    it "renders failed with red style" do
      tx = mock_transaction(status: "failed")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("failed")
      expect(rendered).to include("bg-red-900")
    end
  end

  describe "token badge" do
    it "renders carbon_coin with emerald style" do
      expect(html).to include("carbon_coin")
      expect(html).to include("text-emerald-400")
    end

    it "renders forest_coin with forest token style" do
      tx = mock_transaction(token_type: "forest_coin")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("forest_coin")
      expect(rendered).to include("text-token-forest")
    end

    it "renders unknown token with zinc style" do
      tx = mock_transaction(token_type: "unknown_coin")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("unknown_coin")
      expect(rendered).to include("text-zinc-400")
    end
  end

  describe "transaction details table" do
    it "displays amount field" do
      expect(html).to include("Amount")
      expect(html).to include("0.005 SCC")
    end

    it "displays token type" do
      expect(html).to include("Token Type")
      expect(html).to include("carbon_coin")
    end

    it "displays blockchain network" do
      expect(html).to include("Blockchain Network")
      expect(html).to include("POLYGON")
    end

    it "displays locked points" do
      expect(html).to include("Locked Points")
      expect(html).to include("10000")
    end

    it "displays to address" do
      expect(html).to include("To Address")
      expect(html).to include("0x1234567890abcdef1234567890abcdef12345678")
    end

    it "displays gas price with wei unit" do
      expect(html).to include("Gas Price")
      expect(html).to include("30 wei")
    end

    it "displays gas used" do
      expect(html).to include("Gas Used")
      expect(html).to include("21000")
    end

    it "displays block number" do
      expect(html).to include("Block Number")
      expect(html).to include("123456")
    end

    it "displays nonce" do
      expect(html).to include("Nonce")
      expect(html).to include("42")
    end

    it "shows a dash for blockchain network when nil" do
      tx = mock_transaction(blockchain_network: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Blockchain Network")
      expect(rendered).to include("—")
    end

    it "shows a dash for gas price when nil" do
      tx = mock_transaction(gas_price: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Gas Price")
      expect(rendered).not_to include(" wei")
    end

    it "shows a dash for sent_at when nil" do
      tx = mock_transaction(sent_at: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Sent At")
      expect(rendered).to include("—")
    end

    it "shows a dash for confirmed_at when nil" do
      tx = mock_transaction(confirmed_at: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Confirmed At")
      expect(rendered).to include("—")
    end
  end

  describe "notes panel" do
    it "shows 'No notes attached.' when notes are nil" do
      expect(html).to include("No notes attached.")
    end

    it "displays notes when present" do
      tx = mock_transaction(notes: "Batch mint for Carpathian cluster")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Batch mint for Carpathian cluster")
    end
  end

  describe "error message panel" do
    it "does not render error section when no error" do
      expect(html).not_to include("Error Message")
    end

    it "renders error message when present" do
      tx = mock_transaction(error_message: "Gas estimation failed: revert")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Error Message")
      expect(rendered).to include("Gas estimation failed: revert")
    end
  end

  describe "wallet info" do
    it "displays tree DID" do
      expect(html).to include("Tree DID")
      expect(html).to include("SNET-00000042")
    end

    it "displays wallet balance" do
      expect(html).to include("Wallet Balance")
      expect(html).to include("12.5")
    end

    it "shows 'No wallet linked.' when wallet is nil" do
      tx = mock_transaction(has_wallet: false)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("No wallet linked.")
    end
  end

  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source for wallet" do
      expect(html).to include("turbo-cable-stream-source")
    end

    it "does not include turbo stream when wallet is nil" do
      tx = mock_transaction(has_wallet: false)
      rendered = render_component(transaction: tx)
      expect(rendered).not_to include("turbo-cable-stream-source")
    end
  end

  describe "lazy-loaded on-chain frame" do
    it "renders turbo frame with correct ID" do
      expect(html).to include("tx_onchain_frame_1")
    end

    it "uses lazy loading" do
      expect(html).to include('loading="lazy"')
    end
  end

  describe "status badge else branch" do
    it "renders unknown status with zinc fallback style" do
      tx = mock_transaction(status: "manual_review")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("bg-zinc-900")
    end
  end
end

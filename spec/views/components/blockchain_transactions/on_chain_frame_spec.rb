# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::OnChainFrame do
  let(:transaction) { mock_transaction }
  let(:html) { render_component(transaction: transaction) }

  def mock_transaction(id: 1, tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                       explorer_url: "https://polygonscan.com/tx/0xabc",
                       blockchain_network: "polygon")
    tx = OpenStruct.new(
      id: id,
      tx_hash: tx_hash,
      explorer_url: explorer_url,
      blockchain_network: blockchain_network
    )
    tx.define_singleton_method(:model_name) { ActiveModel::Name.new(BlockchainTransaction) }
    tx.define_singleton_method(:to_key) { [ id ] }
    tx.define_singleton_method(:to_param) { id.to_s }
    tx.define_singleton_method(:solana_network?) { blockchain_network == "solana" }
    tx.define_singleton_method(:celo_network?) { blockchain_network == "celo" }
    tx
  end

  describe "turbo frame" do
    it "renders turbo frame with correct ID" do
      expect(html).to include("tx_onchain_frame_1")
    end

    it "uses correct frame ID for different transaction IDs" do
      tx = mock_transaction(id: 42)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("tx_onchain_frame_42")
    end
  end

  describe "when tx_hash is present" do
    it "displays the transaction hash" do
      expect(html).to include("0xabcdef1234567890abcdef1234567890abcdef12")
    end

    it "displays Transaction Hash label" do
      expect(html).to include("Transaction Hash")
    end

    it "links to explorer URL" do
      expect(html).to include("https://polygonscan.com/tx/0xabc")
    end

    it "includes aria-label on explorer link" do
      expect(html).to include("aria-label")
    end

    it "includes focus-visible accessibility ring" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "explorer name" do
    it "displays Polygonscan for polygon network" do
      expect(html).to include("View on Polygonscan")
    end

    it "displays Solana Explorer for solana network" do
      tx = mock_transaction(blockchain_network: "solana",
                            explorer_url: "https://explorer.solana.com/tx/abc")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("View on Solana Explorer")
    end

    it "displays Celo Explorer for celo network" do
      tx = mock_transaction(blockchain_network: "celo",
                            explorer_url: "https://celoscan.io/tx/abc")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("View on Celo Explorer")
    end
  end

  describe "when tx_hash is not present" do
    let(:transaction) { mock_transaction(tx_hash: nil) }

    it "shows pending message" do
      expect(html).to include("Transaction not yet submitted to chain.")
    end

    it "does not show explorer link" do
      expect(html).not_to include("View on")
    end

    it "does not show Transaction Hash label" do
      expect(html).not_to include("Transaction Hash")
    end
  end

  describe "on-chain verification header" do
    it "displays On-Chain Verification title" do
      expect(html).to include("On-Chain Verification")
    end
  end
end

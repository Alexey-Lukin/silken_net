# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::OnChainFrame do
  let(:transaction) { build_transaction }
  let(:html) { render_component(transaction: transaction) }

  # [TEST.12] Реальний незбережений `BlockchainTransaction`, і мок брехав ТРИЧІ.
  # (1) `blockchain_network: "polygon"` — значення, якого модель не приймає
  #     (`inclusion: %w[evm solana celo]`); мережа Polygon виражається як `evm`.
  # (2) `explorer_url` подавався НАПРЯМУ, тоді як модель його ДЕРИВУЄ з мережі
  #     та хешу — саме це перетворення не перевірялось ніколи.
  # (3) `solana_network?`/`celo_network?` були рукописні, тобто фікстура оголошувала
  #     предикати, які реальний запис віддає сам.
  def build_transaction(id: 1, tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                        blockchain_network: "evm")
    BlockchainTransaction.new(id: id, tx_hash: tx_hash, blockchain_network: blockchain_network)
  end

  describe "turbo frame" do
    it "renders turbo frame with correct ID" do
      expect(html).to include("tx_onchain_frame_1")
    end

    it "uses correct frame ID for different transaction IDs" do
      tx = build_transaction(id: 42)
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
      expect(html).to include("https://polygonscan.com/tx/0xabcdef1234567890abcdef1234567890abcdef12")
    end

    # [I18N.1] Свідомо БЕЗ aria-label: видимий текст лінка сам описовий, а
    # aria перекривав би його англійською в усіх локалях (04_04 §9, виняток UI.3).
    it "relies on the localised visible text, not an aria-label" do
      expect(html).to include("View on Polygonscan →")
      expect(html).not_to include("aria-label")
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
      tx = build_transaction(blockchain_network: "solana")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("View on Solana Explorer")
    end

    it "displays Celo Explorer for celo network" do
      tx = build_transaction(blockchain_network: "celo")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("View on Celo Explorer")
    end
  end

  describe "when tx_hash is not present" do
    let(:transaction) { build_transaction(tx_hash: nil) }

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

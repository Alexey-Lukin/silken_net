# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Show do
  let(:component_class) { described_class }
  let(:wallet) { mock_wallet }
  let(:transactions) { [ mock_tx ] }
  let(:html) { render_component(wallet: wallet, transactions: transactions) }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_wallet(id: 1, scc_balance: 42.5)
    wallet = OpenStruct.new(id: id, scc_balance: scc_balance)
    wallet.define_singleton_method(:model_name) { ActiveModel::Name.new(Wallet) }
    wallet.define_singleton_method(:to_key) { [ id ] }
    wallet.define_singleton_method(:to_param) { id.to_s }
    wallet
  end

  def mock_tx(id: 1, token_type: "carbon_coin", status: "confirmed", amount: "0.005",
              tx_hash: "0xabcdef1234567890abcdef", explorer_url: "https://polygonscan.com/tx/0x123")
    tx = OpenStruct.new(
      id: id, token_type: token_type, status: status, amount: amount,
      tx_hash: tx_hash, explorer_url: explorer_url, created_at: Time.current
    )
    tx.define_singleton_method(:model_name) { ActiveModel::Name.new(BlockchainTransaction) }
    tx.define_singleton_method(:to_key) { [ id ] }
    tx
  end


  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source for wallet transactions" do
      expect(html).to include("turbo-cable-stream-source")
    end
  end

  describe "transaction ledger" do
    it "displays transaction table headers" do
      expect(html).to include("Type")
      expect(html).to include("Amount")
      expect(html).to include("Status")
      expect(html).to include("TX Hash")
      expect(html).to include("Timestamp")
    end

    it "renders transaction rows" do
      expect(html).to include("carbon_coin")
      expect(html).to include("0.005")
    end

    it "uses dom_id for transaction rows" do
      expect(html).to include("blockchain_transaction_1")
    end

    it "includes transactions_ledger tbody ID" do
      expect(html).to include('id="transactions_ledger"')
    end
  end

  describe "empty ledger" do
    let(:transactions) { [] }

    it "shows empty state message" do
      expect(html).to include("No transactions detected")
    end
  end

  describe "on-chain actions" do
    it "renders sync button with aria-label" do
      expect(html).to include("Sync with Polygon")
      expect(html).to include("aria-label")
    end

    it "renders export CSV button" do
      expect(html).to include("Export CSV Ledger")
    end

    it "includes focus-visible accessibility styles" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "lazy loading frames" do
    it "includes balance frame with lazy loading" do
      expect(html).to include("wallet_balance_frame_1")
    end

    it "includes metadata frame with lazy loading" do
      expect(html).to include("wallet_metadata_frame_1")
    end
  end
end

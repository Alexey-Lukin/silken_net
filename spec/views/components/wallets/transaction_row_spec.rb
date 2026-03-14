# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::TransactionRow do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  def mock_tx(token_type: "carbon_coin", status: "confirmed", amount: "0.005",
              tx_hash: "0xabcdef1234567890abcdef", explorer_url: "https://polygonscan.com/tx/0x123")
    tx = OpenStruct.new(
      id: 42,
      token_type: token_type,
      status: status,
      amount: amount,
      tx_hash: tx_hash,
      explorer_url: explorer_url,
      created_at: Time.current
    )
    # Enable dom_id support for OpenStruct mock
    def tx.model_name
      ActiveModel::Name.new(BlockchainTransaction)
    end
    def tx.to_key
      [ id ]
    end
    tx
  end

  describe "token type styling" do
    it "renders carbon_coin with emerald style" do
      html = render_component(tx: mock_tx(token_type: "carbon_coin"))
      expect(html).to include("bg-emerald-900/20")
      expect(html).to include("text-emerald-400")
    end

    it "renders forest_coin with token-forest style" do
      html = render_component(tx: mock_tx(token_type: "forest_coin"))
      expect(html).to include("bg-token-forest/20")
      expect(html).to include("text-token-forest")
    end

    it "renders unknown token type with zinc fallback" do
      html = render_component(tx: mock_tx(token_type: "mystery_coin"))
      expect(html).to include("bg-zinc-900")
      expect(html).to include("text-zinc-400")
    end
  end

  describe "status color" do
    it "renders confirmed status in emerald" do
      html = render_component(tx: mock_tx(status: "confirmed"))
      expect(html).to include("text-emerald-500")
    end

    it "renders processing status with warning pulse" do
      html = render_component(tx: mock_tx(status: "processing"))
      expect(html).to include("text-status-warning-text")
      expect(html).to include("animate-pulse")
    end

    it "renders sent status with warning pulse" do
      html = render_component(tx: mock_tx(status: "sent"))
      expect(html).to include("text-status-warning-text")
      expect(html).to include("animate-pulse")
    end

    it "renders pending status in gray" do
      html = render_component(tx: mock_tx(status: "pending"))
      expect(html).to include("text-gray-400")
    end

    it "renders failed status in red" do
      html = render_component(tx: mock_tx(status: "failed"))
      expect(html).to include("text-red-500")
    end
  end

  describe "transaction hash display" do
    it "truncates long tx hashes to 16 chars" do
      html = render_component(tx: mock_tx(tx_hash: "0xabcdef1234567890abcdef"))
      expect(html).to include("0xabcdef12345678…")
    end

    it "links to explorer URL" do
      html = render_component(tx: mock_tx(explorer_url: "https://polygonscan.com/tx/0x123"))
      expect(html).to include("https://polygonscan.com/tx/0x123")
    end

    it "shows PENDING_BLOCK when hash is nil" do
      html = render_component(tx: mock_tx(tx_hash: nil))
      expect(html).to include("PENDING_BLOCK")
    end
  end

  describe "rendering" do
    let(:html) { render_component(tx: mock_tx) }

    it "includes the dom_id of the transaction in the row id" do
      expect(html).to include("blockchain_transaction_42")
    end

    it "displays the token type" do
      expect(html).to include("carbon_coin")
    end

    it "displays the amount" do
      expect(html).to include("0.005")
    end

    it "uses text-micro for status instead of arbitrary sizes" do
      expect(html).to include("text-micro")
      expect(html).not_to include("text-[")
    end

    it "uses extracted row_classes method" do
      expect(html).to include("hover:bg-emerald-950/10")
      expect(html).to include("transition-colors")
    end
  end
end

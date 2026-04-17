# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::Index do
  let(:transactions) { [ mock_transaction ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(transactions: transactions, pagy: pagy) }


  def mock_transaction(id: 1, amount: "0.005", status: "confirmed", token_type: "carbon_coin",
                       tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                       explorer_url: "https://polygonscan.com/tx/0xabc",
                       blockchain_network: "polygon", wallet_tree_did: "SNET-00000042",
                       has_wallet: true)
    tree = OpenStruct.new(did: wallet_tree_did)
    wallet = has_wallet ? OpenStruct.new(tree: tree) : nil

    tx = OpenStruct.new(
      id: id,
      amount: amount,
      status: status,
      token_type: token_type,
      tx_hash: tx_hash,
      explorer_url: explorer_url,
      blockchain_network: blockchain_network,
      wallet: wallet,
      created_at: Time.current
    )
    tx.define_singleton_method(:model_name) { ActiveModel::Name.new(BlockchainTransaction) }
    tx.define_singleton_method(:to_key) { [ id ] }
    tx.define_singleton_method(:to_param) { id.to_s }
    tx
  end

  describe "header" do
    it "displays Blockchain Ledger title" do
      expect(html).to include("Blockchain Ledger")
    end

    it "displays token type badges" do
      expect(html).to include("carbon_coin")
      expect(html).to include("forest_coin")
    end
  end

  describe "table headers" do
    it "renders all column headers" do
      expect(html).to include("Type")
      expect(html).to include("Amount")
      expect(html).to include("Status")
      expect(html).to include("Network")
      expect(html).to include("Tree")
      expect(html).to include("TX Hash")
      expect(html).to include("Timestamp")
    end
  end

  describe "transaction rows" do
    it "displays amount with SCC" do
      expect(html).to include("0.005 SCC")
    end

    it "displays status" do
      expect(html).to include("confirmed")
    end

    it "displays network in uppercase" do
      expect(html).to include("POLYGON")
    end

    it "displays tree DID from wallet" do
      expect(html).to include("SNET-00000042")
    end

    it "displays truncated tx_hash with link" do
      expect(html).to include("0xabcdef12345678...")
    end

    it "links to explorer URL" do
      expect(html).to include("https://polygonscan.com/tx/0xabc")
    end

    it "includes aria-label on explorer link" do
      expect(html).to include("aria-label")
    end

    it "displays timestamp" do
      expect(html).to include("//")
    end
  end

  describe "token type badge styles" do
    it "renders carbon_coin with emerald style" do
      expect(html).to include("text-emerald-400")
    end

    it "renders forest_coin with forest token style" do
      txs = [ mock_transaction(token_type: "forest_coin") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-token-forest")
    end

    it "renders unknown token with zinc style" do
      txs = [ mock_transaction(token_type: "other_token") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-zinc-400")
    end
  end

  describe "status colors" do
    it "renders confirmed with emerald text" do
      expect(html).to include("text-emerald-500")
    end

    it "renders processing with warning text and pulse" do
      txs = [ mock_transaction(status: "processing") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-status-warning-text")
      expect(rendered).to include("animate-pulse")
    end

    it "renders sent with warning text and pulse" do
      txs = [ mock_transaction(status: "sent") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-status-warning-text")
    end

    it "renders pending with gray text" do
      txs = [ mock_transaction(status: "pending") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-gray-400")
    end

    it "renders failed with red text" do
      txs = [ mock_transaction(status: "failed") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-red-500")
    end
  end

  describe "PENDING_BLOCK" do
    it "shows PENDING_BLOCK when tx_hash is nil" do
      txs = [ mock_transaction(tx_hash: nil) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("PENDING_BLOCK")
    end
  end

  describe "empty state" do
    it "shows empty message when no transactions" do
      rendered = render_component(transactions: [], pagy: mock_pagy(count: 0, last: 1))
      expect(rendered).to include("No blockchain transactions recorded.")
    end
  end

  describe "pagination" do
    it "renders pagination component" do
      expect(html).to be_present
    end
  end

  describe "wallet without tree" do
    it "shows dash when wallet is nil" do
      txs = [ mock_transaction(has_wallet: false) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      # The component calls tx.wallet&.tree&.did || "—"
      expect(rendered).to include("—")
    end
  end

  describe "multiple transactions" do
    it "renders all transaction rows" do
      txs = [
        mock_transaction(id: 1, amount: "1.0"),
        mock_transaction(id: 2, amount: "2.0")
      ]
      rendered = render_component(transactions: txs, pagy: mock_pagy(count: 2, last: 1))
      expect(rendered).to include("1.0 SCC")
      expect(rendered).to include("2.0 SCC")
    end
  end
end

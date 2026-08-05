# SPDX-License-Identifier: AGPL-3.0-or-later
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
      created_at: Time.current,
      # Тікер ДЕЛЕГУЄТЬСЯ реальній моделі, а не переписується тут: другий вивід тієї
      # самої мапи означав би, що друкарська помилка в одному з них зелена назавжди
      # (`04_04 §12.14`). ⚠️ Стеля: решта цього мока лишається `OpenStruct` із
      # вигаданими типами (`amount` рядком; `blockchain_network: "polygon"` — значення,
      # яке `validates inclusion: %w[evm solana celo]` відкидає). Повний перехід на
      # реальний запис зроблено в `wallets/transaction_row_spec.rb`; тут борг → `00_07` TEST.12.
      ticker: BlockchainTransaction.new(token_type: token_type).ticker
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

    # `cusd` — третє РЕАЛЬНЕ значення enum'а, якому стилю не заведено. Доти тут
    # стояв вигаданий `"other_token"`: фолбек перевірявся входом, неможливим у
    # проді, а єдиний вхід, яким він досяжний насправді, — ніяк.
    it "renders cusd — the styleless enum value — with the zinc fallback" do
      txs = [ mock_transaction(token_type: "cusd") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-zinc-400")
    end
  end

  # Статус іде через спільний `Views::Shared::UI::StatusBadge` (I18N.1, 2026-08-05):
  # приватна кольор-мапа цього компонента була побайтовою копією тієї, що в
  # `Wallets::TransactionRow`, і обидві дублювали централізовану. Піни тепер на
  # СЕМАНТИЧНІ токени бейджа, а не на сирі `text-gray-400`/`text-red-500`.
  describe "status colors" do
    # ⚠️ Доти цей приклад пінив `text-emerald-500` і був ЗЕЛЕНИЙ через сусідню
    # колонку DID, яка носить той самий клас — тобто ловив правильну сторінку,
    # але не той елемент. Пін на токен бейджа цього повторити не може.
    it "renders confirmed with the success token" do
      expect(html).to include("bg-status-success")
    end

    it "renders processing with the warning token and pulse" do
      txs = [ mock_transaction(status: "processing") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
      expect(rendered).to include("animate-pulse")
    end

    it "renders sent with the info token" do
      txs = [ mock_transaction(status: "sent") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-info")
    end

    it "renders pending with the warning token" do
      txs = [ mock_transaction(status: "pending") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
    end

    it "renders failed with the danger token" do
      txs = [ mock_transaction(status: "failed") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-danger")
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

  # Раніше цей приклад називав `manual_review` «unknown status» і пінив сірий
  # фолбек — тобто фіксував дефект як норму. Це реальний AASM-стан грошового
  # шляху, і він був тьмянішим за доброякісний `pending`.
  describe "manual_review — double-spend guard" do
    it "renders more prominently than a benign pending transaction" do
      rendered = render_component(transactions: [ mock_transaction(status: "manual_review") ], pagy: pagy)

      expect(rendered).to include("text-status-warning-text")
      expect(rendered).to include("animate-pulse")
    end
  end

  describe "blockchain_network fallback" do
    it "shows a dash when blockchain_network is nil" do
      txs = [ mock_transaction(blockchain_network: nil) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("—")
    end
  end

  describe "pagination url_helper" do
    it "renders pagination links with correct path" do
      multi_pagy = mock_pagy(count: 50, page: 1, last: 3)
      rendered = render_component(transactions: [ mock_transaction ], pagy: multi_pagy)
      expect(rendered).to include("page=2")
    end
  end
end

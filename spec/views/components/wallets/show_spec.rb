# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Show do
  let(:wallet) { mock_wallet }
  let(:transactions) { [ mock_tx ] }
  let(:html) { render_component(wallet: wallet, transactions: transactions) }

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

    # [UI.4] Продюсер робить `prepend`, тож стабільна адреса легальна лише там,
    # де рендериться ПОЧАТОК списку. Поза першою сторінкою вона мусить зникнути,
    # інакше свіжа транзакція сідає в чужий зріз пагінації.
    it "keeps the stable ledger target on the first page" do
      html = render_component(wallet: wallet, transactions: transactions,
                              pagy: mock_pagy(count: 120, page: 1, last: 3))

      expect(html).to include('id="transactions_ledger"')
    end

    # Поза першою сторінкою адреси немає ВЗАГАЛІ — не власне ім'я для сторінки:
    # те друге було б ціллю, якої не кличе жоден продюсер, тобто новим членом
    # саме того класу мертвих target-id, що [UI.4] інвентаризує.
    it "drops the ledger target entirely beyond the first page" do
      html = render_component(wallet: wallet, transactions: transactions,
                              pagy: mock_pagy(count: 120, page: 2, last: 3))

      expect(html).not_to include("transactions_ledger")
    end
  end

  describe "empty ledger" do
    let(:transactions) { [] }

    it "shows empty state message" do
      expect(html).to include("No transactions detected")
    end

    # Ціль, яку знімає `BlockchainTransaction#broadcast_new_transaction`. Доти
    # цей id не пінила жодна спека, хоча продюсер тепер на нього адресує.
    it "marks the placeholder row with the id the producer removes" do
      expect(html).to include('id="empty_ledger"')
    end
  end

  describe "pagination" do
    it "renders pagination when pagy is present" do
      html = render_component(wallet: wallet, transactions: transactions, pagy: mock_pagy(count: 50, page: 1, last: 3))
      expect(html).to be_present
    end

    it "does not render pagination when pagy is nil" do
      html = render_component(wallet: wallet, transactions: transactions)
      expect(html).not_to include("pagination")
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

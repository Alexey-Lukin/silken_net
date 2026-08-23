# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactionBlueprint, type: :model do
  before do
    silence_broadcasts!(:tree_map)
  end

  let(:tree) { create(:tree) }
  let(:wallet) { tree.wallet }
  let(:tx_hash) { "0x" + SecureRandom.hex(32) }
  let(:blockchain_transaction) do
    create(:blockchain_transaction, wallet: wallet, amount: 42.5,
                                    token_type: :carbon_coin, status: :confirmed,
                                    tx_hash: tx_hash, notes: "Carbon credit minting")
  end

  # 🔴 [ARCH.101] Напрямок — властивість контракту, не оздоба: `amount`
  # валідовано `greater_than: 0`, тож slash-інтент їде ДОДАТНИМ і знак його не
  # видає. Без цього поля машинний споживач не відрізнить спалення від емісії
  # на поверхні, чиє призначення саме аудит.
  #
  # Пін іде ПАРОЮ навмисно: одне значення предиката доводить, що ключ є, і нічого
  # не каже про те, чи він ДИСКРИМІНУЄ — саме так виглядав би захардкоджений
  # `false`. Обидва боки будуються тим самим дискримінатором, що й
  # `net_minted_supply` (`sourceable_type`), тож пін звірений із SQL-агрегатом.
  describe "напрямок руху [ARCH.101]" do
    let(:contract) { create(:naas_contract) }
    let(:burn_tx) do
      create(:blockchain_transaction, wallet: wallet, amount: 3.0,
                                      sourceable: contract, status: :confirmed)
    end

    it "позначає спалення в обох вʼю" do
      %i[index show].each do |view|
        parsed = JSON.parse(described_class.render(burn_tx, view: view))
        expect(parsed["burn"]).to be(true), "#{view}: спалення не позначене"
      end
    end

    it "не позначає емісію — і саме ця половина доводить дискримінацію" do
      %i[index show].each do |view|
        parsed = JSON.parse(described_class.render(blockchain_transaction, view: view))
        expect(parsed["burn"]).to be(false), "#{view}: емісія позначена спаленням"
      end
    end

    # Ліхтар: обидві сторони мусять мати ОДНАКОВУ додатну суму, інакше пін
    # непомітно спирався б на знак, якого в схемі не буває.
    it "розрізняє їх при ОДНАКОВІЙ додатній сумі" do
      mint = create(:blockchain_transaction, wallet: wallet, amount: 3.0, status: :confirmed)

      expect(burn_tx.amount).to eq(mint.amount)
      expect(burn_tx.amount).to be_positive
      expect(JSON.parse(described_class.render(burn_tx, view: :index))["burn"]).to be(true)
      expect(JSON.parse(described_class.render(mint, view: :index))["burn"]).to be(false)
    end
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(blockchain_transaction, view: :index)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(blockchain_transaction.id)
    end

    it "includes transaction fields" do
      expect(parsed["amount"]).to eq("42.5")
      expect(parsed["token_type"]).to eq("carbon_coin")
      expect(parsed["status"]).to eq("confirmed")
      expect(parsed["tx_hash"]).to eq(tx_hash)
      expect(parsed["to_address"]).to eq(blockchain_transaction.to_address)
    end

    it "includes created_at" do
      expect(parsed).to have_key("created_at")
    end

    it "includes computed explorer_url" do
      expect(parsed["explorer_url"]).to eq("https://polygonscan.com/tx/#{tx_hash}")
    end

    it "includes computed tree_did from wallet association" do
      expect(parsed["tree_did"]).to eq(tree.did)
    end

    it "excludes show-only fields" do
      expect(parsed).not_to have_key("notes")
      expect(parsed).not_to have_key("error_message")
      expect(parsed).not_to have_key("gas_price")
      expect(parsed).not_to have_key("wallet")
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(blockchain_transaction, view: :show)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(blockchain_transaction.id)
    end

    it "includes all detail fields" do
      expect(parsed["amount"]).to eq("42.5")
      expect(parsed["token_type"]).to eq("carbon_coin")
      expect(parsed["status"]).to eq("confirmed")
      expect(parsed["tx_hash"]).to eq(tx_hash)
      expect(parsed["to_address"]).to eq(blockchain_transaction.to_address)
      expect(parsed["notes"]).to eq("Carbon credit minting")
    end

    it "includes timestamps" do
      expect(parsed).to have_key("created_at")
      expect(parsed).to have_key("updated_at")
    end

    it "includes gas and block fields" do
      expect(parsed).to have_key("gas_price")
      expect(parsed).to have_key("gas_used")
      expect(parsed).to have_key("cumulative_gas_cost")
      expect(parsed).to have_key("block_number")
      expect(parsed).to have_key("nonce")
    end

    it "includes timing fields" do
      expect(parsed).to have_key("sent_at")
      expect(parsed).to have_key("confirmed_at")
      expect(parsed).to have_key("locked_points")
    end

    it "includes computed explorer_url" do
      expect(parsed["explorer_url"]).to eq("https://polygonscan.com/tx/#{tx_hash}")
    end

    it "includes nested wallet with :with_tree view" do
      wallet_data = parsed["wallet"]
      expect(wallet_data).to be_a(Hash)
      expect(wallet_data["id"]).to eq(wallet.id)
      expect(wallet_data["balance"]).to eq(wallet.balance.to_s)
      expect(wallet_data["tree"]).to be_a(Hash)
      expect(wallet_data["tree"]["did"]).to eq(tree.did)
    end

    it "excludes index-only fields" do
      expect(parsed).not_to have_key("tree_did")
    end
  end

  describe "explorer_url when tx_hash is nil" do
    let(:blockchain_transaction) do
      create(:blockchain_transaction, wallet: wallet, tx_hash: nil, status: :pending)
    end

    it "returns nil for explorer_url in :index" do
      parsed = JSON.parse(described_class.render(blockchain_transaction, view: :index))
      expect(parsed["explorer_url"]).to be_nil
    end
  end

  describe "tree_did when wallet has no tree" do
    it "handles safe navigation gracefully" do
      allow(blockchain_transaction.wallet).to receive(:tree).and_return(nil)
      parsed = JSON.parse(described_class.render(blockchain_transaction, view: :index))
      expect(parsed["tree_did"]).to be_nil
    end
  end

  describe "tree_did when wallet itself is nil" do
    it "returns nil when wallet is nil" do
      allow(blockchain_transaction).to receive(:wallet).and_return(nil)
      parsed = JSON.parse(described_class.render(blockchain_transaction, view: :index))
      expect(parsed["tree_did"]).to be_nil
    end
  end

  describe "collection rendering" do
    let!(:transactions) do
      create_list(:blockchain_transaction, 3, wallet: wallet)
    end

    it "renders an array of transactions" do
      parsed = JSON.parse(described_class.render(transactions, view: :index))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed).to all(include("explorer_url", "tree_did"))
    end
  end
end

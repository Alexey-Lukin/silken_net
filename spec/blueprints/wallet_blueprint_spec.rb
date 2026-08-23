# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletBlueprint, type: :model do
  before do
    silence_broadcasts!(:tree_map)
  end

  let(:tree) { create(:tree) }
  let(:wallet) { tree.wallet }

  describe "default view" do
    subject(:parsed) { JSON.parse(described_class.render(wallet)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(wallet.id)
    end

    it "includes balance" do
      expect(parsed["balance"]).to eq(wallet.balance.to_s)
    end

    it "includes crypto_public_address" do
      expect(parsed["crypto_public_address"]).to eq(wallet.crypto_public_address)
    end

    it "does not include tree association in default view" do
      expect(parsed).not_to have_key("tree")
    end
  end

  describe ":with_tree view" do
    subject(:parsed) { JSON.parse(described_class.render(wallet, view: :with_tree)) }

    it "includes base fields" do
      expect(parsed["balance"]).to eq(wallet.balance.to_s)
      expect(parsed["crypto_public_address"]).to eq(wallet.crypto_public_address)
    end

    it "includes nested tree in :minimal view" do
      tree_data = parsed["tree"]
      expect(tree_data).to be_a(Hash)
      expect(tree_data["id"]).to eq(tree.id)
      expect(tree_data["did"]).to eq(tree.did)
      expect(tree_data["status"]).to eq(tree.status)
    end

    it "tree does not include fields beyond :minimal" do
      tree_data = parsed["tree"]
      expect(tree_data).not_to have_key("latitude")
      expect(tree_data).not_to have_key("current_stress")
    end
  end

  describe "collection rendering" do
    let(:trees) { create_list(:tree, 2) }

    it "renders an array of wallets" do
      wallets = trees.map(&:wallet)
      parsed = JSON.parse(described_class.render(wallets))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(2)
    end
  end

  describe ":balance view" do
    subject(:parsed) { JSON.parse(described_class.render(wallet, view: :balance)) }

    it "includes balance fields with correct values" do
      expect(parsed).to include("id", "scc_balance", "locked_balance", "available_balance", "esg_retired_balance")
      expect(parsed["scc_balance"].to_d).to eq(wallet.scc_balance)
      expect(parsed["locked_balance"].to_d).to eq(wallet.locked_balance)
      expect(parsed["available_balance"].to_d).to eq(wallet.available_balance)
      expect(parsed["esg_retired_balance"].to_d).to eq(wallet.esg_retired_balance)
    end

    it "does not include tree or crypto_public_address" do
      expect(parsed).not_to have_key("tree")
      expect(parsed).not_to have_key("crypto_public_address")
    end
  end

  describe ":metadata view" do
    subject(:parsed) { JSON.parse(described_class.render(wallet, view: :metadata)) }

    it "includes metadata fields with correct values" do
      expect(parsed).to include("id", "crypto_public_address", "locked_balance", "available_balance", "esg_retired_balance", "network")
      expect(parsed["crypto_public_address"]).to eq(wallet.crypto_public_address)
      expect(parsed["locked_balance"].to_d).to eq(wallet.locked_balance)
    end

    it "returns Polygon network name" do
      expect(parsed["network"]).to eq("Polygon PoS (Mainnet)")
    end
  end
end

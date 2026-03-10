# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletBlueprint, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:tree) { create(:tree) }
  let(:wallet) { tree.wallet }

  describe "default view" do
    subject(:parsed) { JSON.parse(described_class.render(wallet)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(wallet.id)
    end

    it "includes balance" do
      expect(parsed["balance"]).to be_a(Numeric)
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
      expect(parsed["balance"]).to be_a(Numeric)
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
end

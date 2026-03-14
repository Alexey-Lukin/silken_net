# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceDisplay do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  def mock_wallet(id: 1, scc_balance: 42.123456, tree_did: "TREE::0xBEEF", org_name: nil)
    tree = tree_did ? OpenStruct.new(did: tree_did) : nil
    org  = org_name ? OpenStruct.new(name: org_name) : nil
    OpenStruct.new(id: id, scc_balance: scc_balance, tree: tree, organization: org)
  end

  describe "balance rendering" do
    let(:html) { render_component(wallet: mock_wallet(scc_balance: 42.123456)) }

    it "displays the SCC balance rounded to 6 decimals" do
      expect(html).to include("42.123456")
    end

    it "displays the SCC currency label" do
      expect(html).to include("SCC")
    end

    it "displays the locked-for tree DID" do
      expect(html).to include("TREE::0xBEEF")
    end
  end

  describe "with organization wallet" do
    let(:html) { render_component(wallet: mock_wallet(tree_did: nil, org_name: "GreenCorp")) }

    it "displays the organization name" do
      expect(html).to include("GreenCorp")
    end
  end

  describe "Turbo sync target ID" do
    let(:html) { render_component(wallet: mock_wallet(id: 99)) }

    it "renders the wallet balance target id" do
      expect(html).to include("wallet_balance_99")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallet: mock_wallet) }

    it "uses text-tiny for labels instead of arbitrary sizes" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[10px]")
    end

    it "uses extracted container_classes method for the outer div" do
      expect(html).to include("border-emerald-900")
      expect(html).to include("bg-zinc-950")
      expect(html).to include("shadow-2xl")
    end

    it "uses gap instead of space-x for balance layout" do
      expect(html).to include("gap-4")
    end
  end
end

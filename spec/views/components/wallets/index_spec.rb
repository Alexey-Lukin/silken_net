# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Index do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_pagy(count: 3, page: 1)
    pagy = OpenStruct.new(count: count, page: page, last: 1, from: 1, to: count, prev: nil, next: nil, vars: { items: 21 })
    pagy.define_singleton_method(:series) { [1] }
    pagy
  end

  def mock_wallet(id: 1, scc_balance: 42.5, locked_balance: 0, esg_retired_balance: 0, tree_did: "SNET-AABBCCDD", org_name: nil, crypto_public_address: "0xDEAD1234BEEF5678")
    tree = tree_did ? OpenStruct.new(did: tree_did) : nil
    org  = org_name ? OpenStruct.new(name: org_name) : nil
    OpenStruct.new(
      id: id,
      scc_balance: scc_balance,
      locked_balance: locked_balance,
      esg_retired_balance: esg_retired_balance,
      tree: tree,
      organization: org,
      crypto_public_address: crypto_public_address
    )
  end

  describe "rendering" do
    let(:wallets) { [mock_wallet(id: 1), mock_wallet(id: 2, tree_did: nil, org_name: "GreenCorp")] }
    let(:html) { render_component(wallets: wallets, pagy: mock_pagy(count: 2), total_liquidity: 100.5) }

    it "renders the Treasury Matrix heading" do
      expect(html).to include("Treasury Matrix")
    end

    it "displays the monitoring description" do
      expect(html).to include("Monitoring the flow of Silken Carbon Coins")
    end

    it "shows total liquidity" do
      expect(html).to include("100.5 SCC")
    end

    it "renders the grid layout for wallet cards" do
      expect(html).to include("grid-cols-1")
    end

    it "renders with fade-in animation" do
      expect(html).to include("animate-in")
    end
  end

  describe "wallet card content" do
    let(:html) { render_component(wallets: [mock_wallet(scc_balance: 99.1234)], total_liquidity: 99.1234) }

    it "displays the SCC balance" do
      expect(html).to include("99.1234")
    end

    it "displays the SCC label" do
      expect(html).to include("SCC")
    end

    it "shows Soldier Wallet label for tree wallets" do
      expect(html).to include("Soldier Wallet")
    end

    it "displays the tree DID as owner name" do
      expect(html).to include("SNET-AABBCCDD")
    end

    it "shows Audit Ledger link" do
      expect(html).to include("Audit Ledger →")
    end
  end

  describe "organization wallet" do
    let(:html) { render_component(wallets: [mock_wallet(tree_did: nil, org_name: "BioForest")], total_liquidity: 0) }

    it "shows Clan Treasury label for org wallets" do
      expect(html).to include("Clan Treasury")
    end

    it "displays the organization name" do
      expect(html).to include("BioForest")
    end
  end

  describe "System Reserve fallback" do
    let(:html) { render_component(wallets: [mock_wallet(tree_did: nil, org_name: nil)], total_liquidity: 0) }

    it "shows System Reserve when no tree or org" do
      expect(html).to include("System Reserve")
    end
  end

  describe "locked balance indicator" do
    it "shows locked balance when > 0" do
      html = render_component(wallets: [mock_wallet(locked_balance: 5.5)], total_liquidity: 0)
      expect(html).to include("🔒")
      expect(html).to include("5.5 locked")
    end

    it "hides locked balance when 0" do
      html = render_component(wallets: [mock_wallet(locked_balance: 0)], total_liquidity: 0)
      expect(html).not_to include("🔒")
    end
  end

  describe "ESG retired balance" do
    it "shows retired balance when > 0" do
      html = render_component(wallets: [mock_wallet(esg_retired_balance: 3.14)], total_liquidity: 0)
      expect(html).to include("♻")
      expect(html).to include("3.14 retired")
    end

    it "hides retired balance when 0" do
      html = render_component(wallets: [mock_wallet(esg_retired_balance: 0)], total_liquidity: 0)
      expect(html).not_to include("♻")
    end
  end

  describe "without pagination" do
    it "renders without pagy when nil" do
      html = render_component(wallets: [mock_wallet], total_liquidity: 0)
      expect(html).to include("Treasury Matrix")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallets: [mock_wallet], total_liquidity: 0) }

    it "uses text-tiny and text-mini for labels" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-mini")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-emerald-700")
    end
  end
end

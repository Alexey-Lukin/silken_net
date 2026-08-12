# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceDisplay do
  def mock_wallet(id: 1, balance: 42.123456, tree_did: "TREE::0xBEEF", org_name: nil)
    tree = tree_did ? OpenStruct.new(did: tree_did) : nil
    org  = org_name ? OpenStruct.new(name: org_name) : nil
    OpenStruct.new(id: id, balance: balance, tree: tree, organization: org)
  end

  describe "balance rendering" do
    # [ARCH.88] Крок джерела = 0.01 (`TreeFamily#weighted_growth_points` округлює
    # нарахування до 2 знаків), тож фікстура несе ДОСЯЖНЕ значення. Доти тут
    # стояло `42.123456` — число, якого жоден живий тракт у колонку не кладе,
    # і пін на «6 знаків» цементував запас СХОВИЩА як точність ПОКАЗУ.
    let(:html) { render_component(wallet: mock_wallet(balance: 42.13)) }

    it "displays the growth-point balance at the source's own step" do
      expect(html).to include("42.13")
    end

    # Дискримінує САМ дім точності: без `formatted_points` тут надрукувалось би
    # «42.123456», тобто шість знаків там, де домен має два.
    it "truncates precision beyond the domain step to POINTS_PRECISION" do
      html = render_component(wallet: mock_wallet(balance: 42.123456))

      expect(html).to include("42.12")
      expect(html).not_to include("42.123456")
    end

    it "displays the GP unit label, never the coin ticker" do
      # [ARCH.88] Пара, що РОЗРІЗНЯЄ: доти пін ловив «SCC» із декоративного
      # водяного знака й лишався зеленим навіть при виправленій мітці.
      expect(html).to include("GP")
      expect(html).not_to include("SCC")
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

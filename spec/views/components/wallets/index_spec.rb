# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Index do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # [TEST.12] Реальний незбережений `Wallet`.
  #
  # 🔴 **Тут жила форма вакуумності, якої вісь доти не мала: пін зелений із
  # ЧУЖОГО КАНАЛУ — з URL-екранованого ДАМПУ самої фікстури.** Ця спека їде
  # через `ApplicationController.renderer` (компонент кличе `wallet_path`), а
  # `OpenStruct#to_param` — це `Object#to_param`, тобто `to_s`: увесь дамп
  # (`#<OpenStruct id=1, balance=99.1234, …>`) потрапляв у `href`, і цифри в
  # ньому segment-safe. Тож `include("99.1234")` проходив, хоча компонент друкує
  # `formatted_points` → «99.12», а такого текстового вузла не існує взагалі.
  # Тим самим каналом живились піни на DID і назву організації.
  #
  # ⚠️ Адреса доти була «0xDEAD1234BEEF5678» — 16 hex-символів при
  # `ETH_ADDRESS_FORMAT`, що вимагає рівно 40.
  def build_wallet(id: 1, balance: 42.5, locked_balance: 0, esg_retired_balance: 0,
                   tree_did: "SNET-AABBCCDD", org_name: nil,
                   crypto_public_address: "0x1234567890ABCDEF1234567890ABCDEF12345678")
    Wallet.new(
      id: id,
      balance: balance,
      locked_balance: locked_balance,
      esg_retired_balance: esg_retired_balance,
      tree: tree_did ? Tree.new(did: tree_did) : nil,
      organization: org_name ? Organization.new(name: org_name) : nil,
      crypto_public_address: crypto_public_address
    )
  end

  describe "rendering" do
    let(:wallets) { [ build_wallet(id: 1), build_wallet(id: 2, tree_did: nil, org_name: "GreenCorp") ] }
    let(:html) { render_component(wallets: wallets, pagy: mock_pagy(count: 2, last: 1), total_liquidity: 100.5) }

    it "renders the Treasury Matrix heading" do
      expect(html).to include("Treasury Matrix")
    end

    it "displays the monitoring description" do
      expect(html).to include("Monitoring the flow of growth points")
    end

    it "shows total liquidity in growth points, not coins" do
      expect(html).to include("100.5 GP")
      expect(html).not_to include("100.5 SCC")
    end

    it "renders the grid layout for wallet cards" do
      expect(html).to include("grid-cols-1")
    end
  end

  describe "wallet card content" do
    let(:html) { render_component(wallets: [ build_wallet(balance: 99.1234) ], total_liquidity: 99.1234) }

    # 🔴 Доти тут стояло `include("99.1234")` — і воно було зелене НЕ від рендеру:
    # компонент друкує `formatted_points` → «99.12», а сирі шість знаків
    # потрапляли в документ лише через `href` (дамп `OpenStruct`). Конверсія
    # завалила цей пін ПЕРШИМ же прогоном — тобто вакуумність доведено падінням,
    # а не міркуванням.
    it "displays the growth-point balance at the domain step" do
      expect(html).to include("99.12")
      expect(html).not_to include("99.1234")
    end

    it "displays the GP unit label, never the coin ticker" do
      # [ARCH.88] Доти цей пін лишався зеленим від рядка total-liquidity навіть
      # при виправленій мітці картки — тепер він розрізняє.
      expect(html).to include("GP")
      expect(html).not_to include("SCC")
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

  # [TEST.12] Обидві нижні гілки ланцюга власника — ЗАХИСТ, не власники (присуд
  # 2026-08-20): за схеми `tree_id NOT NULL` + `did NOT NULL` вони недосяжні для
  # чесного рядка й стережуть лише рядок повз AR (insert_all-клас ARCH.75).
  # Незбережений `Wallet.new` — єдиний спосіб їх відрендерити, і це не хиба
  # фікстури, а модель загрози цих прикладів.
  describe "guard branch: row past AR without a tree" do
    let(:html) { render_component(wallets: [ build_wallet(tree_did: nil, org_name: "BioForest") ], total_liquidity: 0) }

    it "falls back to the denormalized org label instead of an empty owner" do
      expect(html).to include("Clan Treasury")
      expect(html).to include("BioForest")
    end
  end

  describe "guard branch: row past AR with neither tree nor org" do
    let(:html) { render_component(wallets: [ build_wallet(tree_did: nil, org_name: nil) ], total_liquidity: 0) }

    it "prints System Reserve as the last guard step" do
      expect(html).to include("System Reserve")
    end
  end

  describe "locked balance indicator" do
    it "shows locked balance when > 0" do
      html = render_component(wallets: [ build_wallet(locked_balance: 5.5) ], total_liquidity: 0)
      expect(html).to include("🔒")
      expect(html).to include("5.5 locked")
    end

    it "hides locked balance when 0" do
      html = render_component(wallets: [ build_wallet(locked_balance: 0) ], total_liquidity: 0)
      expect(html).not_to include("🔒")
    end
  end

  describe "ESG retired balance" do
    it "shows retired balance when > 0" do
      html = render_component(wallets: [ build_wallet(esg_retired_balance: 3.14) ], total_liquidity: 0)
      expect(html).to include("♻")
      expect(html).to include("3.14 retired")
    end

    it "hides retired balance when 0" do
      html = render_component(wallets: [ build_wallet(esg_retired_balance: 0) ], total_liquidity: 0)
      expect(html).not_to include("♻")
    end
  end

  describe "without pagination" do
    it "renders without pagy when nil" do
      html = render_component(wallets: [ build_wallet ], total_liquidity: 0)
      expect(html).to include("Treasury Matrix")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallets: [ build_wallet ], total_liquidity: 0) }

    it "uses text-tiny and text-mini for labels" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-mini")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-gaia-text-muted")
    end
  end
end

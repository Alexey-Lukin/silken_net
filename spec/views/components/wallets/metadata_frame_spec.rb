# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::MetadataFrame do
  # [TEST.12] Реальний незбережений `Wallet`.
  #
  # 🔴 **Тут жила ЦЕНТРАЛЬНА форма всієї осі: `available_balance` подавався
  # НАПРЯМУ, хоча це не колонка, а ДЕРИВАЦІЯ** (`Wallet#available_balance` =
  # `balance - locked_balance`). Тобто фікстура оголошувала світ, у якому
  # «доступно» і «заблоковано» — два незалежні факти, тоді як у моделі перше
  # МІСТИТЬ друге. Найгостріший наслідок був не в числі: приклад із
  # `locked_balance: 10.5` не подавав `balance` взагалі, тож при реальному
  # записі порушував DB-CHECK `wallets_balance_invariants` (`locked <= balance`)
  # — тобто описував рядок, якого в базі бути НЕ МОЖЕ.
  #
  # Тепер годуються ДЖЕРЕЛА (`balance` + `locked_balance`), а `available`
  # виводиться моделлю — саме те віднімання, яке доти не виконувалось ніколи.
  def build_wallet(id: 1, crypto_public_address: "0xDEAD1234BEEF5678CAFE", balance: 42.5, locked_balance: 0, esg_retired_balance: 0)
    Wallet.new(
      id: id,
      crypto_public_address: crypto_public_address,
      balance: balance,
      locked_balance: locked_balance,
      esg_retired_balance: esg_retired_balance
    )
  end

  describe "rendering" do
    let(:html) { render_component(wallet: build_wallet) }

    it "renders the turbo frame tag with correct id" do
      expect(html).to include("wallet_metadata_frame_1")
    end

    it "displays the Blockchain Identity heading" do
      expect(html).to include("Blockchain Identity")
    end

    it "displays the Polygon Address label" do
      expect(html).to include("Polygon Address")
    end

    it "displays the Network name" do
      expect(html).to include("Polygon PoS (Mainnet)")
    end

    # 🔴 Пін доти був вакуумний за АДРЕСОЮ: `Views::Shared::Web3::Address` кладе
    # ПОВНУ адресу в `title:` і `data-clipboard-content-value`, а у видимий текст
    # друкує СКОРОЧЕНУ. Тобто `include(<повна>)` зелений від атрибута, і зламане
    # скорочення його не завалить. Пінимо обидві половини окремо.
    it "renders the full address for copy/title, and the truncated one on screen" do
      expect(html).to include("0xDEAD1234BEEF5678CAFE")
      expect(html).to include("0xDEAD…CAFE")
    end
  end

  describe "balance display" do
    # `balance` 100.0 − `locked` 10.5 ⇒ `available` **89.5 виводиться моделлю**.
    # Доти ці два числа подавались незалежно, і їхня узгодженість була ВИПАДКОВОЮ
    # збіжністю у фікстурі, а не властивістю системи.
    let(:html) do
      render_component(wallet: build_wallet(balance: 100.0, locked_balance: 10.5, esg_retired_balance: 5.25))
    end

    it "displays Locked Balance label" do
      expect(html).to include("Locked Balance")
    end

    it "displays locked balance value" do
      expect(html).to include("10.5")
    end

    it "displays Available Balance label" do
      expect(html).to include("Available Balance")
    end

    it "displays available balance value" do
      expect(html).to include("89.5")
    end

    it "displays ESG Retired label" do
      expect(html).to include("ESG Retired")
    end

    it "displays ESG retired balance value" do
      expect(html).to include("5.25")
    end

    # [ARCH.88 → ARCH.95] Картка несе ДВІ шкали, і саме тому пін тут не про
    # «яка одиниця присутня», а про те, що кожна стоїть при СВОЇЙ величині.
    # Доти приклад звався «never the coin ticker» і забороняв «SCC» на всій картці
    # — тобто цементував твердження «усі три величини балові», яке присуд ARCH.95
    # спростував: `esg_retired_balance` рахує погашені МОНЕТИ.
    it "labels the points scales as GP and the retired coins as SCC" do
      expect(html).to include("GP")
      expect(html).to include("SCC")
    end

    # Негативна половина, що пережила присуд і несе його: тікер монети не сміє
    # заповзти на балові рядки — саме там він і був би завищенням у 10 000×.
    it "never prints the coin ticker beside a points balance" do
      points_rows = html.scan(%r{<p[^>]*>\s*[\d.]+\s*GP\s*</p>})
      expect(points_rows.size).to eq(2)
      expect(points_rows.join).not_to include("SCC")
    end
  end

  describe "not provisioned wallet" do
    it "shows NOT_PROVISIONED when address is blank" do
      # ⚠️ Тут стояв `define_singleton_method(:crypto_public_address) { nil }` під
      # коментарем «Override present? for nil» — рядок, що НЕ робив ані того, що
      # казав (жодного `present?` він не чіпав), ані взагалі чогось: значення вже
      # `nil` із конструктора. Мертва підробка, знята разом із `OpenStruct`.
      html = render_component(wallet: build_wallet(crypto_public_address: nil))
      expect(html).to include("NOT_PROVISIONED")
    end

    it "shows NOT_PROVISIONED when address is empty string" do
      wallet = build_wallet(crypto_public_address: "")
      html = render_component(wallet: wallet)
      expect(html).to include("NOT_PROVISIONED")
    end
  end

  describe "turbo frame id uniqueness" do
    it "uses wallet id in frame id" do
      html = render_component(wallet: build_wallet(id: 99))
      expect(html).to include("wallet_metadata_frame_99")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallet: build_wallet) }

    it "uses text-tiny for labels" do
      expect(html).to include("text-tiny")
    end

    it "uses gaia design tokens for text" do
      expect(html).to include("text-gaia-text-muted")
    end

    it "uses status-warning-text for locked balance" do
      expect(html).to include("text-status-warning-text")
    end

    it "uses gaia-primary for available balance" do
      expect(html).to include("text-gaia-primary")
    end
  end
end

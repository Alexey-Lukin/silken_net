# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceFrame do
  # [TEST.12] Реальний незбережений `Wallet`.
  #
  # ⚠️ Тут стояла найагресивніша підробка з родини — `OpenStruct` плюс рукописні
  # `model_name`/`to_key`/`to_param` через `define_singleton_method`, — і всі три
  # синглтони були **МЕРТВІ**: `BalanceFrame` будує `turbo_frame_tag` із РЯДКА
  # (`"wallet_balance_frame_#{@wallet.id}"`), а `BalanceDisplay` читає той самий
  # `id`. Жоден із трьох не викликався жодного разу. Тобто фікстура вдавала
  # модель без потреби — чиста інерція форми, скопійована від сусіда.
  #
  # 🔴 Дорожче за це: `available_balance` і власник (`tree`/`organization`) не
  # оголошувались ВЗАГАЛІ, тож делегований `BalanceDisplay` друкував нуль і
  # порожній рядок «Locked for: » у КОЖНОМУ прикладі файлу — при тому, що
  # `available_balance` є деривацією `balance - locked_balance`.
  def build_wallet(id: 1, balance: 42.5, locked_balance: 0.0, esg_retired_balance: 0.0)
    Wallet.new(
      id: id,
      balance: balance,
      locked_balance: locked_balance,
      esg_retired_balance: esg_retired_balance,
      tree: Tree.new(did: "SNET-0000BEEF")
    )
  end

  describe "turbo frame wrapper" do
    it "wraps content in a turbo frame tag with the wallet id" do
      html = render_component(wallet: build_wallet(id: 7))
      expect(html).to include("wallet_balance_frame_7")
    end

    it "uses wallet id 1 in the frame id" do
      html = render_component(wallet: build_wallet(id: 1))
      expect(html).to include("wallet_balance_frame_1")
    end

    it "uses a unique frame id per wallet" do
      html_a = render_component(wallet: build_wallet(id: 10))
      html_b = render_component(wallet: build_wallet(id: 99))
      expect(html_a).to include("wallet_balance_frame_10")
      expect(html_b).to include("wallet_balance_frame_99")
    end
  end

  describe "balance display delegation" do
    # [ARCH.88] Значення кратне кроку джерела (0.01) — див. `balance_display_spec`.
    let(:html) { render_component(wallet: build_wallet(balance: 12.35)) }

    it "renders the growth-point balance from BalanceDisplay" do
      expect(html).to include("12.35")
    end

    it "renders the GP unit label" do
      # [ARCH.88] Пара, що РОЗРІЗНЯЄ: доти пін ловив «SCC» із декоративного
      # водяного знака й лишався зеленим навіть при виправленій мітці.
      expect(html).to include("GP")
      expect(html).not_to include("SCC")
    end
  end

  # 🔴 Доти обидва приклади робили `include(<число>)` по ВСЬОМУ документу, а
  # `BalanceDisplay` друкує ЧОТИРИ числа поспіль — тобто пін не знав, яке з них
  # упіймав, і був сліпий до перестановки величин місцями. Тепер кожен цілить у
  # свою мітку разом зі значенням.
  describe "locked balance" do
    it "shows the locked balance next to its own label" do
      html = render_component(wallet: build_wallet(balance: 42.5, locked_balance: 5.0))

      expect(html).to include("5.0")
      expect(html).to include("Locked")
    end
  end

  describe "esg retired balance" do
    it "shows the retired balance next to its own label" do
      html = render_component(wallet: build_wallet(esg_retired_balance: 3.25))

      expect(html).to include("3.25")
      expect(html).to include("ESG")
    end
  end

  # 🔴 Делегація доти доводилась лише тим, що якесь число потрапило в документ.
  # `available_balance` — ДЕРИВАЦІЯ (`balance - locked_balance`), і на моці вона
  # не виконувалась ніколи: поле не оголошувалось, `OpenStruct` віддавав `nil`,
  # а `formatted_points(nil)` мовчки друкував «0.0».
  describe "delegated derivation" do
    it "derives the available balance through the delegated component" do
      html = render_component(wallet: build_wallet(balance: 42.5, locked_balance: 12.5))

      expect(html).to include("30.0")
    end
  end
end

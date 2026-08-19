# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::BalanceDisplay do
  # [TEST.12] Реальний незбережений `Wallet` — фабрика свідомо не взята (тягне
  # `tree → cluster → organization` і б'є в БД заради рендера).
  #
  # 🔴 **Три з чотирьох величин доти не перевірялись ЖОДНИМ прикладом.** Мок
  # оголошував самий `balance`, а компонент читає ще `locked_balance`,
  # `available_balance` і `esg_retired_balance` — `OpenStruct` мовчки віддавав на
  # них `nil`. Найгірше з трьох — `available_balance`: це не колонка, а
  # ДЕРИВАЦІЯ (`balance - locked_balance`), тож саме віднімання не виконувалось
  # ніколи. Тепер годується джерело, і воно виводиться.
  #
  # ⚠️ Значення тримають CHECK-констрейнт схеми (`locked_balance <= balance`) —
  # фікстура, що його порушує, описує рядок, якого в БД бути не може.
  def build_wallet(id: 1, balance: 42.13, locked: 12.13, retired: 5.5, tree_did: "SNET-0000BEEF", org_name: nil)
    # `Tree::DID_FORMAT` = /\ASNET-[0-9A-F]{8}\z/ — доти фікстура несла
    # `TREE::0xBEEF`, тобто рядок, якого модель не прийняла б у жодному сценарії
    # (ще й `normalize_identifier :did` робить `upcase`).
    tree = tree_did ? Tree.new(did: tree_did) : nil
    org  = org_name ? Organization.new(name: org_name) : nil

    Wallet.new(
      id: id,
      balance: balance,
      locked_balance: locked,
      esg_retired_balance: retired,
      tree: tree,
      organization: org
    )
  end

  describe "balance rendering" do
    # [ARCH.88] Крок джерела = 0.01 (`TreeFamily#weighted_growth_points` округлює
    # нарахування до 2 знаків), тож фікстура несе ДОСЯЖНЕ значення. Доти тут
    # стояло `42.123456` — число, якого жоден живий тракт у колонку не кладе,
    # і пін на «6 знаків» цементував запас СХОВИЩА як точність ПОКАЗУ.
    let(:html) { render_component(wallet: build_wallet(balance: 42.13)) }

    it "displays the growth-point balance at the source's own step" do
      expect(html).to include("42.13")
    end

    # Дискримінує САМ дім точності: без `formatted_points` тут надрукувалось би
    # «42.123456», тобто шість знаків там, де домен має два.
    it "truncates precision beyond the domain step to POINTS_PRECISION" do
      html = render_component(wallet: build_wallet(balance: 42.123456))

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
      expect(html).to include("SNET-0000BEEF")
    end

    # 🔴 Три величини, яких доти не бачив ЖОДЕН приклад: мок оголошував самий
    # `balance`, тож решта приходила `nil`. Найдорожча з них — `available_balance`,
    # бо це ДЕРИВАЦІЯ (`balance - locked_balance`), тобто фікстура доти вирішувала
    # за модель, а саме віднімання не виконувалось ніколи.
    it "derives the available balance instead of taking it from the fixture" do
      expect(html).to include("30.0")
    end

    it "displays the locked and ESG-retired balances" do
      expect(html).to include("12.13")
      expect(html).to include("5.5")
    end
  end

  describe "with organization wallet" do
    let(:html) { render_component(wallet: build_wallet(tree_did: nil, org_name: "GreenCorp")) }

    it "displays the organization name" do
      expect(html).to include("GreenCorp")
    end
  end

  describe "Turbo sync target ID" do
    let(:html) { render_component(wallet: build_wallet(id: 99)) }

    it "renders the wallet balance target id" do
      expect(html).to include("wallet_balance_99")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(wallet: build_wallet) }

    it "uses text-tiny for labels instead of arbitrary sizes" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[10px]")
    end

    it "uses extracted container_classes method for the outer div" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface-sunken")
      expect(html).to include("shadow-2xl")
    end

    it "uses gap instead of space-x for balance layout" do
      expect(html).to include("gap-4")
    end
  end
end

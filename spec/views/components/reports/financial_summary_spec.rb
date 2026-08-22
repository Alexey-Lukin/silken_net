# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::FinancialSummary do
  # Склад ключів і типи — з `Api::V1::ReportsController#financial_summary`, який
  # цей хеш і будує: `Organization#total_contracted` підсумовує `total_funding.to_f`,
  # тобто Float; лічильники — Integer; `blockchain_transactions` приходить із
  # `group(:status).count`.
  #
  # ✅ [ARCH.90, присуд founder 2026-08-13] Розходження ЗАКРИТО, і фікстура тепер
  # описує обидві половини присуду. Доти вона стояла тут як ліхтар: `network_emission`
  # був у ній САМЕ ТОМУ, що компонент його не читав (чотири ключі проти пʼяти), а
  # пін на відсутність свідомо не ставився, щоб не зацементувати дірку.
  # Тепер: (1) блок рендериться в HTML, тож чотири формати одного ендпоінта
  # нарешті кажуть одне; (2) премія з нього ПІШЛА — вона ані мережева, ані емісія,
  # а платформенний агрегат у звіті орендаря ще й є pooled-фактором
  # (`securities_review` F8), тож у `@data` вона живе окремим org-скоупленим
  # ключем `insurance_premiums_paid_usdc`.
  def report_data(total_contracted: 75_000.0, active_contracts: 12, total_contracts: 20,
                  insurance_premiums_paid_usdc: 4_200,
                  blockchain_transactions: nil, network_emission: nil)
    {
      total_contracted: total_contracted,
      active_contracts: active_contracts,
      total_contracts: total_contracts,
      insurance_premiums_paid_usdc: insurance_premiums_paid_usdc,
      blockchain_transactions: blockchain_transactions || {
        total: 500, confirmed: 480, pending: 15, failed: 5
      },
      network_emission: network_emission || {
        total_minted_scc: 1_250, total_burned_scc: 300, net_deflation: -950
      }
    }
  end

  let(:org)  { Organization.new(name: "GreenFund") }
  let(:data) { report_data }
  let(:html) { render_component(organization: org, data: data) }

  describe "header section" do
    it "renders Financial Summary Report label" do
      expect(html).to include("Financial Summary Report")
    end

    it "renders organization name" do
      expect(html).to include("GreenFund")
    end

    it "renders generated timestamp" do
      expect(html).to include("Generated:")
    end
  end

  describe "stat cards" do
    it "renders Total Contracted stat card" do
      # Service wording, not investment wording — BIZ.22 / 00_04 §1. The label moved
      # from "Total Invested"; the i18n KEY (`metrics.total_invested`) deliberately did
      # not, since keys are never shown to a user.
      expect(html).to include("Total Contracted")
    end

    # Плата за послугу номінована в USD (`00_04 §5`) — і саме тут підпис це каже
    # ПРАВДИВО, на відміну від сусідів, де той самий стовпчик підписано карбоновим
    # тікером (`I18N.1`). Пін тримає обидві половини одним вузлом: масштаб Float
    # (модель підсумовує `.to_f`) і саму одиницю, тож «уніфікація» підпису під SCC
    # почервонить поіменно.
    it "prints the contracted sum as a Float beside its USD unit" do
      expect(html).to include(%(<span class="text-tiny text-gaia-text-muted font-mono">USD</span>))
      expect(html).to include(">75000.0<")
    end

    it "renders Active Contracts stat card" do
      expect(html).to include("Active Contracts")
    end

    it "renders Total Contracts stat card" do
      expect(html).to include("Total Contracts")
    end
  end

  describe "blockchain breakdown table" do
    it "renders Blockchain Transactions Breakdown heading" do
      expect(html).to include("Blockchain Transactions Breakdown")
    end

    it "renders Total Transactions row" do
      expect(html).to include("Total Transactions")
    end

    it "renders Confirmed row" do
      expect(html).to include("Confirmed")
    end

    it "renders Pending row" do
      expect(html).to include("Pending")
    end

    it "renders Failed row" do
      expect(html).to include("Failed")
    end

    it "renders total count" do
      expect(html).to include("500")
    end

    it "renders confirmed count" do
      expect(html).to include("480")
    end

    it "renders pending count" do
      expect(html).to include("15")
    end

    # 🔴 Доти цей приклад був `include("5")` — вакуумний ЗА ПОБУДОВОЮ: «5» лежить
    # усередині «500» і «15» із сусідніх рядків, тож він проходив при будь-якій
    # поведінці. Пін тепер бере рядок цілком, тобто звʼязує МІТКУ зі ЗНАЧЕННЯМ:
    # підміна `tx[:failed]` на сусідній ключ червонить поіменно.
    it "binds the failed count to its own row" do
      expect(html).to include(
        %(<td class="p-4 text-status-danger-accent">Failed</td><td class="p-4 text-right font-bold text-status-danger-accent">5</td>)
      )
    end
  end

  # [ARCH.90] Половина, якої в цьому файлі не було ніколи — і саме її відсутність
  # тримала розходження чотирьох форматів невидимим для сюїти.
  describe "network emission block" do
    it "renders the on-chain figures the exports have always printed" do
      expect(html).to include("Network Emission")
      expect(html).to include("1250")
      expect(html).to include("300")
      expect(html).to include("-950")
    end

    it "states whose figures these are" do
      # 🔴 Несучий пін, не косметика: єдиною підказкою доти було слово «Network»
      # у заголовку — а поруч у тій самій секції стояла премія ПЛАТФОРМИ, тож
      # читач не мав як зрозуміти, що числа не його.
      expect(html).to include("not this organization")
    end

    it "keeps the premium out of the network block and shows it as the org's own" do
      expect(html).to include("Insurance Premiums Paid")
      expect(html).to include("4200")
      # Негативна половина: повернення премії в мережевий блок червонить тут.
      expect(html).not_to include("Total Premiums")
    end

    it "stays silent when the emission data is absent" do
      # Гілка `return if ne.blank?` — без цього приклада вона непокрита, а
      # порожній blok на екрані виглядав би як «нуль емісії», тобто твердження.
      html_without = render_component(organization: org, data: report_data(network_emission: {}))
      expect(html_without).not_to include("Network Emission")
    end
  end

  describe "footer" do
    it "renders generated at footer" do
      expect(html).to include("Report generated at")
    end

    it "includes organization name in footer" do
      expect(html).to include("GreenFund")
    end
  end
end

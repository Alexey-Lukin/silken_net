# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::FinancialSummary do
  # Склад ключів і типи — з `Api::V1::ReportsController#financial_summary`, який
  # цей хеш і будує: `Organization#total_contracted` підсумовує `total_funding.to_f`,
  # тобто Float; лічильники — Integer; `blockchain_transactions` приходить із
  # `group(:status).count`.
  #
  # 🔴 `network_emission` стоїть тут САМЕ ТОМУ, що компонент його не читає: доти
  # фікстуру складали з ЧИТАНЬ компонента, а не з ЗАПИСІВ контролера, і при
  # чотирьох ключах проти пʼяти питання «а де пʼятий» із сюїти не ставилось.
  # Відповідь — цілий блок (Minted/Burned SCC · Premiums USDC · Net Deflation),
  # який CSV, PDF і JSON того самого екшена друкують, а HTML не має ніколи
  # (`00_07` ARCH.90). Пін на його відсутність СВІДОМО не ставиться — він
  # зацементував би дірку; фікстура лише перестає її ховати.
  def report_data(total_contracted: 75_000.0, active_contracts: 12, total_contracts: 20,
                  blockchain_transactions: nil, network_emission: nil)
    {
      total_contracted: total_contracted,
      active_contracts: active_contracts,
      total_contracts: total_contracts,
      blockchain_transactions: blockchain_transactions || {
        total: 500, confirmed: 480, pending: 15, failed: 5
      },
      network_emission: network_emission || {
        total_minted_scc: 1_250, total_burned_scc: 300, total_premiums_usdc: 4_200, net_deflation: -950
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
      # Service wording, not investment wording — BIZ.22 / 07_01 §1. The label moved
      # from "Total Invested"; the i18n KEY (`metrics.total_invested`) deliberately did
      # not, since keys are never shown to a user.
      expect(html).to include("Total Contracted")
    end

    # Плата за послугу номінована в USD (`07_01 §5`) — і саме тут підпис це каже
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
        %(<td class="p-4 text-red-400">Failed</td><td class="p-4 text-right font-bold text-red-400">5</td>)
      )
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

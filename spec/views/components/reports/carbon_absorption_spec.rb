# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::CarbonAbsorption do
  # Типи взято з `Api::V1::ReportsController#carbon_absorption`, який і будує цей
  # хеш: `wallets.sum(:balance)` над колонкою `numeric` віддає BigDecimal, решта —
  # `count`/`cached_trees_count`, тобто Integer. Доти вся четвірка подавалась
  # Integer'ом, і питання «як BigDecimal доїжджає до розмітки» з сюїти поставити
  # було неможливо (`ARCH.89`: Phlex тоді не вмів друкувати BigDecimal узагалі —
  # корінь знято в `ApplicationComponent#format_object`, `04_04 §2`).
  def report_data(total_carbon_points: BigDecimal("9800"), wallets_count: 45,
                  trees_active: 280, trees_total: 320)
    {
      total_carbon_points: total_carbon_points,
      wallets_count: wallets_count,
      trees_active: trees_active,
      trees_total: trees_total
    }
  end

  let(:org)  { Organization.new(name: "EcoDAO") }
  let(:data) { report_data }
  let(:html) { render_component(organization: org, data: data) }

  describe "header section" do
    it "renders Carbon Absorption Report label" do
      expect(html).to include("Carbon Absorption Report")
    end

    it "renders organization name" do
      expect(html).to include("EcoDAO")
    end

    it "renders generated timestamp" do
      expect(html).to include("Generated:")
    end
  end

  describe "stat cards" do
    # ⛔ Підпис під цією ж карткою (`…_sub`) каже «SCC», хоча величина — бали
    # росту: мітка чесна, sub — ні. ⚠️ ПІДСТАВА ЗМІНИЛАСЬ 2026-08-15: присуд ARCH.88 ухвалено й ID в архіві, тобто блокування мертве — але САМ СИМПТОМ живий (`total_carbon_points_sub: SCC` у локалях при величині `wallets.sum(:balance)`), тож пін лишається не поставленим через незакритий ДЕФЕКТ, а не через відкритий присуд. Доти писалось: не ставиться, доки не
    # ухвалено присуд `ARCH.88` — інакше зелений пін зацементує брехливу одиницю.
    it "renders Total Carbon Points stat card" do
      expect(html).to include("Total Carbon Points")
    end

    it "renders Active Wallets stat card" do
      expect(html).to include("Active Wallets")
    end

    it "renders Active Trees stat card" do
      expect(html).to include("Active Trees")
    end

    it "renders Total Trees stat card" do
      expect(html).to include("Total Trees")
    end
  end

  describe "metrics table" do
    # Ціль — сама КОМІРКА, не документ: те саме число стоїть ще й в `aria-label`
    # картки, куди воно приходить інтерполяцією (а та кличе `to_s` завжди), тож
    # пін по документу лишався б зеленим і після зняття `to_s` із комірки.
    it "prints the BigDecimal aggregate in the value cell" do
      expect(html).to include(%(<td class="p-4 text-right text-gaia-text-subtle">9800.0</td>))
    end

    it "renders wallets count" do
      expect(html).to include("45")
    end

    it "renders active trees count" do
      expect(html).to include("280")
    end

    it "renders total trees count" do
      expect(html).to include("320")
    end

    it "renders Trees Currently Online row label" do
      expect(html).to include("Trees Currently Online")
    end

    it "renders Trees Deployed row label" do
      expect(html).to include("Trees Deployed")
    end
  end

  describe "footer" do
    it "renders generated at footer" do
      expect(html).to include("Report generated at")
    end

    it "includes organization name in footer" do
      expect(html).to include("EcoDAO")
    end
  end
end

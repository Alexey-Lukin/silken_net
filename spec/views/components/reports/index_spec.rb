# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Index do
  # [TEST.12] Реальна незбережена `Organization` — компонент читає з неї рівно
  # `name`, але підробка тут була безпідставною: модель віддає це поле сама.
  def build_org(id: 1, name: "ForestDAO")
    Organization.new(id: id, name: name)
  end

  # 🔴 **Фікстура ліпилась із того, що компонент ЧИТАЄ, а не з того, що
  # контролер ПЕРЕДАЄ — і пропущений ключ ховав не хибне значення, а ЦІЛУ
  # ГІЛКУ.** `ReportsController` кладе ВІСІМ ключів, мок оголошував шість:
  # бракувало `clusters_measured`/`clusters_total`, тож
  # `measurement_coverage(nil, nil)` віддавав `nil`, і підпис покриття
  # [ARCH.84] не рендерився в ЖОДНОМУ прикладі файлу. Так само недосяжною була
  # гілка `health_score: nil` («не виміряно»).
  #
  # Детектор механічний і дешевий: **звір МНОЖИНУ ключів фікстури з тією, що
  # будує контролер** — правило «бери значення з рядка контролера» стосувалось
  # ЗНАЧЕНЬ і про повноту набору мовчало.
  def build_summary(total_trees: 300, health_score: 0.88, total_carbon_points: 12_500,
                    total_contracted: 50_000, total_clusters: 7, under_threat: false,
                    clusters_measured: 5, clusters_total: 7)
    {
      total_trees: total_trees,
      total_clusters: total_clusters,
      health_score: health_score,
      clusters_measured: clusters_measured,
      clusters_total: clusters_total,
      total_carbon_points: total_carbon_points,
      total_contracted: total_contracted,
      under_threat: under_threat
    }
  end

  let(:org)     { build_org }
  let(:summary) { build_summary }
  let(:html)    { render_component(organization: org, summary: summary) }

  describe "header section" do
    it "renders the Archive Reports Hub heading" do
      expect(html).to include("The Archive")
    end

    it "renders organization name" do
      expect(html).to include("ForestDAO")
    end
  end

  describe "performance stats" do
    it "renders Monitored Trees stat card" do
      expect(html).to include("Monitored Trees")
    end

    it "renders Health Score stat card" do
      expect(html).to include("Health Score")
    end

    # [ARCH.88] Величина = sum(:balance), тобто БАЛИ росту. Ім'я прикладу тут
    # само було твердженням — і брехливим, тож правиться разом з ассертом.
    it "renders accrued growth points, never «SCC Minted»" do
      expect(html).to include("Growth Points Accrued")
      expect(html).not_to include("SCC Minted")
    end

    it "renders Contracted Amount stat card" do
      expect(html).to include("Contracted Amount")
    end

    it "renders Sectors stat card" do
      expect(html).to include("Sectors")
    end

    it "renders Threat Level as CLEAR when no threat" do
      expect(html).to include("CLEAR")
    end

    it "renders Threat Level as ACTIVE when under_threat is true" do
      html = render_component(organization: org, summary: build_summary(under_threat: true))
      expect(html).to include("ACTIVE")
    end

    # 🔴 У всьому файлі доти не було ЖОДНОГО піна на значення — перевірялись самі
    # мітки, ще й через `aria-label`, тобто зелені навіть при знищеному
    # текстовому вузлі. Тож підміна будь-якого ключа `summary` на сусідній
    # проходила непоміченою.
    it "renders the values, not just their labels" do
      expect(html).to include("300")
      expect(html).to include("12500")
      expect(html).to include("50000")
    end
  end

  # 🔴 Обидві гілки доти були НЕДОСЯЖНІ: фікстура не подавала
  # `clusters_measured`/`clusters_total`, тож `measurement_coverage` завжди
  # віддавав `nil` і підпис покриття не рендерився ніколи. [ARCH.84]
  describe "measurement honesty [ARCH.84]" do
    # ⚠️ Пін цілить у САМ підпис покриття, а не в числа: «5» і «7» присутні в
    # документі й з інших карток. Перша редакція цього прикладу ще й несла
    # негативну половину `not_to include("Health Score: ")` — і вона не могла
    # пройти НІКОЛИ, бо `StatCard` кладе в `aria-label` рядок «Health Score:
    # 0.88 …», тобто цей підрядок є при будь-якій поведінці. Спіймано падінням.
    it "shows the coverage when only part of the clusters is measured" do
      expect(html).to include("5 of 7 measured")
    end

    # Повне покриття СВІДОМО не друкує підпис (`measured == total` → nil):
    # «виміряно все» не потребує застереження.
    it "stays silent about coverage when every cluster is measured" do
      html = render_component(organization: org, summary: build_summary(clusters_measured: 7, clusters_total: 7))

      expect(html).to include("Health Score")
    end

    # Друга недосяжна гілка: без виміру картка мусить сказати це СЛОВАМИ, а не
    # порожнім вузлом — інакше `aria-label` стає «Health Score: » і замовкає.
    it "says «not measured» instead of rendering an empty value" do
      html = render_component(organization: org, summary: build_summary(health_score: nil))

      expect(html).to include(I18n.t("ui.measurement.not_measured"))
    end
  end

  describe "report cards" do
    it "renders Carbon Absorption Report card" do
      expect(html).to include("Carbon Absorption Report")
    end

    it "renders Financial Summary Report card" do
      expect(html).to include("Financial Summary Report")
    end

    it "renders Available Reports heading" do
      expect(html).to include("Available Reports")
    end

    it "renders View link for carbon absorption" do
      expect(html).to include("carbon_absorption")
    end

    it "renders CSV export link" do
      expect(html).to include(".csv")
    end

    it "renders PDF export link" do
      expect(html).to include(".pdf")
    end
  end
end

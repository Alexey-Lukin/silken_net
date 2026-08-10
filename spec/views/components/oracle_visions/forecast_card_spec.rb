# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe OracleVisions::ForecastCard do
  # [TEST.12] Реальний незбережений `AiInsight`, а не `OpenStruct`: мок подавав
  # `insight_type` поза enum'ом (enum має рівно чотири значення), `probability_score`
  # цілим при колонці `numeric` (→ BigDecimal) і `target_date` як `Time`, тоді як
  # колонка — `date`. Останнє й ховало живий дефект: картка друкувала «// 00:00 UTC»
  # як годину прогнозу, а спека пінила вигаданий час, якого модель не віддає.
  def mock_insight(
    insight_type: "drought_probability",
    probability_score: 74,
    target_date: Date.new(2025, 8, 15),
    summary: "Severe moisture deficit expected in sector.",
    yield_impact: "-0.12%"
  )
    AiInsight.new(
      insight_type: insight_type,
      probability_score: probability_score,
      target_date: target_date,
      summary: summary,
      prediction_data: { "yield_impact" => yield_impact }
    )
  end

  def render_component(insight:)
    component_class.new(insight: insight).call
  end

  describe "insight_type badge" do
    it "renders the insight_type label" do
      html = render_component(insight: mock_insight(insight_type: "drought_probability"))
      expect(html).to include("drought_probability")
    end

    it "displays the insight_type in uppercase styling" do
      html = render_component(insight: mock_insight(insight_type: "carbon_yield_forecast"))
      expect(html).to include("carbon_yield_forecast")
    end
  end

  # [TEST.12] Колонка `probability_score` — `numeric`, тобто BigDecimal: ціле 40
  # рендериться «40.0%», а не «40%». Доти мок подавав Integer, тож питання «як ТИП
  # доходить до екрана» з сюїти неможливо було поставити. Піни нижче фіксують саме
  # прод-рендер; чи прибирати хвостовий нуль — косметика, 00_07 UI.13.
  describe "probability_score display" do
    it "renders the probability score as percentage" do
      html = render_component(insight: mock_insight(probability_score: 40))
      expect(html).to include("40.0%")
    end

    it "renders a fractional score without rounding it away" do
      html = render_component(insight: mock_insight(probability_score: 87.5))
      expect(html).to include("87.5%")
    end

    it "uses the confidence bar width matching score" do
      html = render_component(insight: mock_insight(probability_score: 65))
      expect(html).to include("width: 65.0%")
    end
  end

  describe "summary" do
    it "renders the insight summary" do
      html = render_component(insight: mock_insight(summary: "Severe moisture deficit expected."))
      expect(html).to include("Severe moisture deficit expected.")
    end
  end

  describe "yield_impact display" do
    it "shows negative yield_impact with red color" do
      html = render_component(insight: mock_insight(yield_impact: "-0.04%"))
      expect(html).to include("text-red-500")
      expect(html).to include("-0.04%")
    end

    it "shows positive yield_impact with emerald color" do
      html = render_component(insight: mock_insight(yield_impact: "+0.08%"))
      expect(html).to include("text-emerald-500")
      expect(html).to include("+0.08%")
    end

    it "includes the SCC suffix" do
      html = render_component(insight: mock_insight(yield_impact: "-0.12%"))
      expect(html).to include("SCC")
    end
  end

  describe "target_date formatting" do
    it "renders date in dd.mm.yyyy format" do
      html = render_component(insight: mock_insight(target_date: Date.new(2025, 3, 7)))
      expect(html).to include("07.03.2025")
    end

    # [TEST.12] Колонка `date` години не несе, тож будь-який надрукований час був би
    # вигаданим («00:00 UTC» для кожного прогнозу). Пін стереже саме відсутність.
    it "does not print a fabricated clock time the column cannot hold" do
      html = render_component(insight: mock_insight(target_date: Date.new(2025, 8, 15)))
      expect(html).to include("15.08.2025")
      expect(html).not_to include("00:00")
      expect(html).not_to include("UTC")
    end
  end

  describe "confidence color" do
    it "uses green color for every insight the enum can actually hold" do
      AiInsight.insight_types.each_key do |type|
        html = render_component(insight: mock_insight(insight_type: type, probability_score: 95))
        expect(html).to include("#10b981")
      end
    end

    # [TEST.12] Червоної гілки більше немає — вона порівнювала `insight_type` з
    # «emergency», значенням поза enum'ом, тож була недосяжна від народження.
    # Пін тримає цю відсутність явно: якщо колись зʼявиться справжній критичний
    # стиль, він мусить приїхати з рішенням (00_07 UI.13), а не тихо повернутись.
    it "has no unreachable emergency styling left" do
      html = render_component(insight: mock_insight(probability_score: 99))
      expect(html).not_to include("#ef4444")
    end
  end

  describe "missing prediction_data" do
    it "falls back to the default yield impact and emerald color" do
      insight = mock_insight(summary: "No structured prediction payload.").tap do |i|
        i.prediction_data = nil
        i.probability_score = 50
      end
      html = render_component(insight: insight)
      expect(html).to include("-0.04%")           # yield_impact_default (dig → nil)
      expect(html).to include("text-emerald-500") # nil.to_f < 0 == false → emerald
    end
  end

  describe "Codex citation strip" do
    it "renders the citation strip when citations exist for the insight" do
      insight = mock_insight
      citation = instance_double(::Codex::Citation)
      relation = double("relation")
      allow(::Codex::Citation).to receive(:for_target).with(insight).and_return(relation)
      allow(relation).to receive(:includes).with(node: :realm).and_return(relation)
      allow(relation).to receive(:limit).with(10).and_return([ citation ])
      allow(relation).to receive(:empty?).and_return(false)

      strip = instance_double(::Codex::Citations::Strip)
      allow(::Codex::Citations::Strip).to receive(:new)
        .with(target: insight, citations: [ citation ])
        .and_return(strip)
      allow(strip).to receive_messages(call: "<div class='cite-strip'>cited</div>".html_safe, render_in: "<div class='cite-strip'>cited</div>".html_safe)

      html = ApplicationController.renderer.render(
        component_class.new(insight: insight), layout: false
      )
      expect(html).to include("border-emerald-900/50")
    end

    it "renders without a citation strip when Codex::Citation is undefined" do
      hide_const("Codex::Citation")
      html = render_component(insight: mock_insight)
      expect(html).not_to include("codex_citations_")
    end
  end
end

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
      expect(html).to include("Drought probability")
    end

    # [I18N.1] Локаль НЕ базова: в англійській мітка й токен розрізняються слабко
    # (обидва містять «forecast»), тож саме тут пін здатен упасти на регресії.
    it "displays a human insight-type label, never the raw enum token" do
      I18n.with_locale(:uk) do
        html = render_component(insight: mock_insight(insight_type: "carbon_yield_forecast"))

        expect(html).to include("Прогноз емісії")
        expect(html).not_to include("carbon_yield_forecast")
      end
    end
  end

  # [TEST.12] Колонка `probability_score` — `numeric`, тобто BigDecimal; доти мок
  # подавав Integer, тож питання «як ТИП доходить до екрана» з сюїти неможливо було
  # поставити. ⚖️ [UI.13] founder 2026-08-14: ціле друкується ЦІЛИМ, дробове лишається
  # дробовим — і формат ОДИН на текст і на `width:`, інакше картка показувала б «40 %»
  # над смугою `width: 40.0%`. НЕ `.round`: кроку джерела не існує (писачів нуль,
  # [ARCH.84]), тож округлення тихо зʼїло б 40.5 у день появи писача.
  describe "probability_score display" do
    it "renders the probability score as percentage" do
      html = render_component(insight: mock_insight(probability_score: 40))
      expect(html).to include("40%")
    end

    it "renders a fractional score without rounding it away" do
      html = render_component(insight: mock_insight(probability_score: 87.5))
      expect(html).to include("87.5%")
    end

    it "uses the confidence bar width matching score" do
      html = render_component(insight: mock_insight(probability_score: 65))
      expect(html).to include("width: 65%")
    end

    # 🔴 [ARCH.84] СЬОМИЙ інстанс класу, і жив він у ТОМУ САМОМУ файлі, що
    # шостий (`yield_impact`): прохід, який полагодив сусіда за двадцять рядків
    # нижче, цього не побачив. Обидва поля мають НУЛЬ писачів —
    # `InsightGeneratorService` створює лише `daily_health_summary`, тож
    # прогноз-інсайт у проді не народжується взагалі.
    #
    # Що саме друкувалось (виміряно рендером): текст — голий «%» без числа,
    # смуга — `style="width: %"`, тобто НЕВАЛІДНИЙ CSS. Модель при цьому
    # чесна (`#confidence_level` → `:n_a`), тож розходився компонент із
    # власною моделлю, а не дані з даними.
    context "when the score was never measured (no writer exists — ARCH.84)" do
      it "names the state instead of printing a bare percent sign" do
        html = render_component(insight: mock_insight(probability_score: nil))

        expect(html).to include(I18n.t("ui.measurement.not_measured"))
        # Ліхтар: саме «%» без числа і був симптомом, тож пін мусить його ловити.
        expect(html).not_to match(/>\s*%\s*</)
      end

      it "does not draw the bar at all — any width is a claim about a measurement" do
        html = render_component(insight: mock_insight(probability_score: nil))

        expect(html).not_to include("width:")
      end

      # ⊥ Дзеркало: доводить, що приклади вище не просто «нічого не малює».
      it "still draws the bar when the score IS measured" do
        expect(render_component(insight: mock_insight(probability_score: 65))).to include("width: 65%")
      end
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
      expect(html).to include("text-status-danger-accent")
      expect(html).to include("-0.04%")
    end

    it "shows positive yield_impact with emerald color" do
      html = render_component(insight: mock_insight(yield_impact: "+0.08%"))
      expect(html).to include("text-gaia-primary-strong")
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

  # [UI.13] Присуд founder 2026-08-14: критичний прогноз має власний стан, і
  # сигнал — ЗНАК `yield_impact`. Обидві попередні спеки цементували стан ДО
  # присуду («зелений для КОЖНОГО типу» · «червоного немає взагалі»), тож
  # переписані: вони були правдиві рівно доти, доки рішення не ухвалили.
  describe "confidence colour follows the yield_impact sign [UI.13]" do
    # Ключове: сигналом є ЗНАК впливу, а НЕ тип інсайту й не ймовірність —
    # тому перебір типів лишається, але доводить тепер протилежне: жоден тип
    # сам по собі кольору не змінює.
    it "лишається primary-strong для будь-якого типу з невідʼємним впливом" do
      AiInsight.insight_types.each_key do |type|
        html = render_component(
          insight: mock_insight(insight_type: type, probability_score: 95, yield_impact: "+12.5%")
        )
        expect(html).to include("text-gaia-primary-strong"), "#{type} мав лишитись primary-strong"
        expect(html).not_to include("text-status-danger-accent")
      end
    end

    it "червоніє на негативному впливі — незалежно від типу й імовірності" do
      html = render_component(
        insight: mock_insight(insight_type: "carbon_yield_forecast", probability_score: 12, yield_impact: "-3.0%")
      )

      expect(html).to include("text-status-danger-accent")
      expect(html).to include("bg-status-danger-accent")
      expect(html).not_to include("text-xs font-mono text-gaia-primary-strong")
    end

    # 🔴 Дім сигналу ОДИН, і саме цю властивість пін і стереже: доти деривація
    # стояла двома копіями, тож картка могла показати червоний ВПЛИВ під
    # зеленим ІНДИКАТОРОМ — два вузли однієї картки, що суперечать одне одному.
    it "тримає індикатор і рядок впливу в ОДНОМУ стані" do
      html = render_component(
        insight: mock_insight(probability_score: 88, yield_impact: "-1.0%")
      )

      expect(html.scan("text-status-danger-accent").size).to be >= 2
      expect(html).not_to include("text-xs font-mono text-gaia-primary-strong")
    end

    # [UI.1] Інлайн-`style:` із кольором — виміряна сліпа зона обох
    # токен-інструментів (вони сканують КЛАСИ). Обидва відомі сайти класу жили
    # саме тут; пін тримає їхню відсутність.
    it "не має інлайн-кольору, невидимого для токен-інструментів" do
      html = render_component(insight: mock_insight(probability_score: 70))

      expect(html).to include("width: 70"), "смуга мусить лишитись інлайн — ширина рантаймова"
      expect(html).not_to match(/style="[^"]*color:/)
    end
  end

  # 🔴 [ARCH.84] Приклад доти ЦЕМЕНТУВАВ дефект: він вимагав, щоб картка без
  # даних друкувала «-0.04%» — вигадане точне число, однакове в чотирьох
  # локалях, — і фарбувала його СМАРАГДОВИМ. Тобто текст стверджував збиток,
  # колір стверджував благополуччя, а виміру не було жодного. Обидві половини
  # були закріплені як контракт.
  describe "missing prediction_data [ARCH.84]" do
    let(:unmeasured) do
      mock_insight(summary: "No structured prediction payload.").tap do |i|
        i.prediction_data = nil
        i.probability_score = 50
      end
    end

    it "називає відсутність виміру, а не вигадує число" do
      html = render_component(insight: unmeasured)

      expect(html).to include(I18n.t("ui.measurement.not_measured"))
      expect(html).not_to include("-0.04%")
    end

    it "тримає НЕЙТРАЛЬНИЙ стан — невиміряне не є ні добрим, ні поганим" do
      html = render_component(insight: unmeasured)

      expect(html).to include("text-gaia-text-subtle")
      expect(html).not_to include("text-xs font-mono text-gaia-primary-strong")
      expect(html).not_to include("text-status-danger-accent")
    end

    # Порожній рядок — той самий стан, що nil: `presence` зводить обидва, бо
    # інакше `"".to_f` дало б 0.0 і картка вітала б порожнечу primary-strong.
    it "рахує порожній рядок відсутністю виміру, а не нулем" do
      insight = mock_insight(yield_impact: "")

      expect(render_component(insight: insight)).to include("text-gaia-text-subtle")
    end
  end
end

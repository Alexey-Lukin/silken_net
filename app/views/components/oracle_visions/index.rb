# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module OracleVisions
  class Index < ApplicationComponent
    # [ARCH.84] Покриття — не оздоба: прогноз рахується лише по деревах із
    # виміряним стресом, тож без `measured`/`total` число мовчки видає себе за
    # твердження про ВЕСЬ ліс. Дефолти `nil` тримають компонент рендерабельним
    # для викликача, який покриття не передав (жоден живий такий не лишився).
    #
    # ⚖️ [UI.7, присуд founder 2026-08-15] Пульт симуляції знято ЦІЛКОМ разом із
    # дією `#simulate`: фічі не існувало на ЖОДНОМУ ярусі — форма цілилась у `div`
    # замість `<turbo-frame>` (Turbo мовчки ігнорує), контролер кликав
    # `SimulationWorker`, якого в дереві немає, а імена повзунків
    # (`variables[temp_offset]`…) не перетинались із permit-списком контролера
    # (`:sigma/:rho/:beta`) — тобто навіть із живим воркером не доїхало б жодне
    # значення. Разом пішла й стрічка `#simulation_results`: вічно порожня коробка
    # з пульсуючою крапкою й підписом «активні симуляції» при нулі продюсерів.
    # Той самий присуд, що в [UI.14]: коли виконавця немає, чесніше не обіцяти.
    def initialize(visions:, emission_forecast:,
                   forecast_measured: nil, forecast_total: nil)
      @visions = visions
      @emission_forecast = emission_forecast
      @forecast_measured = forecast_measured
      @forecast_total = forecast_total
    end

    def view_template
      div(class: "space-y-6") do
        header_section

        if @visions.any?
          @visions.each { |vision| render OracleVisions::ForecastCard.new(insight: vision) }
        else
          render_empty_state
        end
      end
    end

    private

    # 🔴 [ARCH.103] Порожнеча тут СТРУКТУРНА, і доти вона не мала голосу взагалі:
    # `@visions.each` по порожньому відношенні не рендерить нічого, тож у проді
    # сторінка показувала самотню шапку й пустоту під нею — читається як «зараз
    # прогнозів немає», тобто як тимчасовий стан.
    #
    # Насправді стан постійний, і роблять його ДВА незалежні механізми:
    #   · писач штампує `AiInsight.reporting_date` = **вчорашню** UTC-добу, а
    #     `scope :upcoming` бере `target_date >= сьогодні` — множини диз'юнктні
    #     за побудовою, тож жоден згенерований рядок сюди не потрапляє НІКОЛИ;
    #   · `InsightGeneratorService` створює лише `daily_health_summary`; три
    #     прогнозні члени enum'а (`drought_probability` · `carbon_yield_forecast` ·
    #     `biodiversity_trend`) не пише ніхто, крім `db/seeds.rb`.
    # Тобто все, що ця сторінка колись показувала, приходило з сідів.
    #
    # ⚖️ Текст свідомо називає ВІДСУТНІСТЬ ВИРОБНИКА, а не «поки порожньо»: доки
    # продуктове питання (чи прогноз-інсайт узагалі наш продукт) відкрите, чесне
    # «виробника немає» щоразу піднімає його власнику, а «зачекайте» — ховає.
    def render_empty_state
      render Views::Shared::UI::EmptyState.new(
        title: t(".empty_title"),
        icon: "◇",
        description: t(".empty_description")
      )
    end

    def header_section
      div(class: "p-6 border border-gaia-border bg-gaia-surface/80 backdrop-blur-md flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted") { t(".title") }
          # [ARCH.84] ⚖️ Заголовну «впевненість ШІ» знято 2026-08-16: значення було
          # ЛІТЕРАЛОМ в аргументі `t(...)` — перший сайт класу, де вигадане число стоїть
          # не в колонці, тож обидва доменні зонди (колонка без писача · одиниця без
          # тракту) були до нього сліпі. Не переведено в «не виміряно», бо це АГРЕГАТ
          # над картками нижче: кожна `ForecastCard` уже показує власну
          # `probability_score` чесно, а прогноз-інсайтів `InsightGeneratorService` не
          # створює взагалі (лише `daily_health_summary`). Четвертий поверх над трьома
          # чесними — той самий клас, що `ARCH.101` зрізав на дашборді.
        end

        # [FINANCIAL ENGINE VISUALIZATION]: Очікуваний врожай
        div(class: "text-right") do
          h4(class: "text-tiny uppercase tracking-widest text-gaia-text-subtle mb-1") { t(".expected_yield") }
          div(class: "flex items-baseline justify-end gap-2") do
            span(class: "text-3xl font-mono text-gaia-text") do
              @emission_forecast
            end
            span(class: "text-xs text-gaia-primary-strong font-light italic") { t(".yield_unit") }
          end

          # [ARCH.84] Підпис покриття зʼявляється ЛИШЕ при частковому вимірі —
          # `measurement_coverage` віддає `nil` на повному (дім — сайт 1 пункту).
          coverage = measurement_coverage(@forecast_measured, @forecast_total)
          p(class: "text-micro text-status-warning-text font-mono mt-1") { coverage } if coverage
        end
      end
    end
  end
end

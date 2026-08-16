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
        @visions.each { |vision| render OracleVisions::ForecastCard.new(insight: vision) }
      end
    end

    private

    def header_section
      div(class: "p-6 border border-emerald-900 bg-black/40 backdrop-blur-md flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-emerald-700") { t(".title") }
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
          h4(class: "text-tiny uppercase tracking-widest text-emerald-800 mb-1") { t(".expected_yield") }
          div(class: "flex items-baseline justify-end gap-2") do
            span(class: "text-3xl font-mono text-emerald-400 drop-shadow-[0_0_8px_rgba(52,211,153,0.5)]") do
              @emission_forecast
            end
            span(class: "text-xs text-emerald-600 font-light italic") { t(".yield_unit") }
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

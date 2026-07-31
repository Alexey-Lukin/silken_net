# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module OracleVisions
  class Index < ApplicationComponent
    # [UI.6] Сторінка відкрита forester+ (`authorize_forester!`), а `#simulate` стоїть
    # за `authorize_admin!, only: [:simulate]` — тобто форестер бачив цілий пульт
    # симуляції, заповнював його й діставав 403 у turbo-frame без пояснення. Дефолт
    # `nil` fail-CLOSED.
    def initialize(visions:, emission_forecast:, clusters:, current_user: nil)
      @visions = visions
      @emission_forecast = emission_forecast
      @clusters = clusters
      @current_user = current_user
    end

    def view_template
      div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8 animate-in zoom-in duration-700") do
        # ЛІВА ПАНЕЛЬ: Стрічка пророцтв
        div(class: "xl:col-span-2 space-y-6") do
          header_section
          @visions.each { |vision| render OracleVisions::ForecastCard.new(insight: vision) }
        end

        # ПРАВА ПАНЕЛЬ: Пульт Симуляції
        div(class: "space-y-6") do
          # [UI.6] Пульт симуляції веде в `#simulate` (admin+), тож форестеру його не
          # показуємо: стрічку прогнозів він бачить далі — вона під гардом сторінки.
          render OracleVisions::SimulationPanel.new(clusters: @clusters) if @current_user&.admin_or_above?
          render_active_simulations_feed
        end
      end
    end

    private

    def header_section
      div(class: "p-6 border border-emerald-900 bg-black/40 backdrop-blur-md flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-emerald-700") { t(".title") }
          p(class: "text-2xl font-light text-emerald-400 mt-2") { t(".confidence", value: "94.2%") }
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
        end
      end
    end

    def render_active_simulations_feed
      div(id: "simulation_results", class: "space-y-4") do
        div(class: "flex items-center gap-2 mb-4") do
          div(class: "w-1 h-1 bg-emerald-500 rounded-full animate-ping")
          h4(class: "text-tiny uppercase text-gray-600 tracking-widest") { t(".active_simulations") }
        end
        # Сюди Turbo Stream буде додавати результати симуляцій
      end
    end
  end
end

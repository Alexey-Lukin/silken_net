# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Telemetry
  class LiveStream < ApplicationComponent
    def view_template
      div(class: "space-y-6 animate-in fade-in duration-1000") do
        header_section

        # Підписка на SolidCable / Turbo Streams.
        turbo_stream_from "telemetry_stream"

        # Контейнер з відносною позицією для накладання Canvas та таблиці.
        div(class: "relative border border-gaia-border bg-gaia-surface min-h-[400px] md:min-h-[600px] overflow-hidden rounded-sm shadow-[0_0_40px_rgba(6,78,59,0.2)]") do
          # 📟 Абсолютний Canvas — ефект "Зеленого дощу" від Stimulus 'matrix-rain'.
          canvas(data: { controller: "matrix-rain" }, class: "absolute inset-0 z-0 opacity-20 pointer-events-none w-full h-full transform-gpu will-change-transform")

          # Радіальний градієнт для глибини (decorative — raw classes allowed).
          div(class: "absolute inset-0 z-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-transparent via-black/80 to-black pointer-events-none", aria_hidden: "true")

          # HUD-таблиця, що "плаває" поверх дощу. Mobile рендериться як
          # стек карток через `gaia-responsive-table` (CSS-only flip).
          div(class: "relative z-10 w-full h-[400px] md:h-[600px] overflow-y-auto md:overflow-x-auto custom-scrollbar") do
            table(class: "gaia-responsive-table w-full text-left font-mono text-tiny md:min-w-[640px]", role: "table") do
              thead(class: "gaia-sticky-thead bg-gaia-surface-sunken/80 backdrop-blur-md text-gaia-text-muted uppercase tracking-widest border-b border-gaia-border shadow-md") do
                tr do
                  th(scope: "col", class: "p-4 w-32 font-medium") { t("telemetry.table.timestamp") }
                  th(scope: "col", class: "p-4 w-40 font-medium") { t("telemetry.table.gateway") }
                  th(scope: "col", class: "p-4 font-medium") { t("telemetry.table.payload") }
                  th(scope: "col", class: "p-4 w-24 text-right font-medium") { t("telemetry.table.status") }
                end
              end

              tbody(id: "telemetry_feed", class: "md:divide-y md:divide-gaia-border") do
                tr(id: "feed_placeholder") do
                  td(colspan: 4, class: "p-12 text-center text-gaia-text-subtle flex flex-col items-center justify-center") do
                    div(class: "w-8 h-8 rounded-full border-b-2 border-gaia-border-strong animate-spin mb-4", aria_hidden: "true")
                    p(class: "italic tracking-widest text-mini") { t(".awaiting") }
                  end
                end
              end
            end
          end
        end
      end
    end

    private


    def header_section
      div(class: "flex flex-col sm:flex-row sm:justify-between sm:items-end gap-3 border-b border-gaia-border pb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted flex items-center gap-2") do
            i(class: "ph ph-broadcast", aria_hidden: "true")
            plain t(".header_eyebrow")
          end
          h2(class: "text-2xl font-light text-gaia-text mt-2") { t(".header_title") }
        end

        div(class: "flex items-center gap-3 bg-gaia-surface-sunken px-4 py-2 border border-gaia-border shadow-[inset_0_0_10px_rgba(6,78,59,0.5)]") do
          div(class: "relative flex h-2 w-2", aria_hidden: "true") do
            span(class: "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75")
            span(class: "relative inline-flex rounded-full h-2 w-2 bg-emerald-500")
          end
          span(class: "font-mono text-mini text-gaia-primary uppercase tracking-widest") { t(".carrier_label") }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Telemetry
  class LiveStream < ApplicationComponent
    def view_template
      div(class: "space-y-6 animate-in fade-in duration-1000") do
        header_section

        # Підписка на SolidCable / Turbo Streams
        turbo_stream_from "telemetry_stream"

        # Основний контейнер із відносною позицією для накладання Canvas і Таблиці
        div(class: "relative border border-emerald-900 bg-black min-h-[400px] md:min-h-[600px] overflow-hidden rounded-sm shadow-[0_0_40px_rgba(6,78,59,0.2)]") do
          # 📟 МАГІЯ: Абсолютний Canvas на фоні для ефекту "Зеленого дощу"
          # Stimulus-контролер 'matrix-rain' оживить цей тег
          canvas(data: { controller: "matrix-rain" }, class: "absolute inset-0 z-0 opacity-20 pointer-events-none w-full h-full")

          # Радіальний градієнт для додаткової глибини
          div(class: "absolute inset-0 z-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-transparent via-black/80 to-black pointer-events-none")

          # Таблиця (HUD), яка "плаває" поверх дощу
          div(class: "relative z-10 w-full h-[400px] md:h-[600px] overflow-y-auto overflow-x-auto custom-scrollbar") do
            table(class: "w-full text-left font-mono text-tiny min-w-[640px]", role: "table") do
              thead(class: "sticky top-0 bg-emerald-950/80 backdrop-blur-md text-emerald-700 uppercase tracking-widest border-b border-emerald-900/50 shadow-md") do
                tr do
                  th(scope: "col", class: "p-4 w-32 font-medium") { "Timestamp" }
                  th(scope: "col", class: "p-4 w-40 font-medium") { "Queen / Gateway" }
                  th(scope: "col", class: "p-4 font-medium") { "Raw CoAP Payload (Hex Stream)" }
                  th(scope: "col", class: "p-4 w-24 text-right font-medium") { "Status" }
                end
              end

              # Сюди UnpackTelemetryWorker (через LogEntry компонент) буде вставляти нові рядки
              tbody(id: "telemetry_feed", class: "divide-y divide-emerald-900/20") do
                tr(id: "feed_placeholder") do
                  td(colspan: 4, class: "p-12 text-center text-emerald-900/60 flex flex-col items-center justify-center") do
                    div(class: "w-8 h-8 rounded-full border-b-2 border-emerald-800 animate-spin mb-4")
                    p(class: "italic tracking-widest text-mini") { "Awaiting Starlink Uplink... CoAP:5683 Listening..." }
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
      div(class: "flex justify-between items-end border-b border-emerald-900/30 pb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-emerald-700 flex items-center gap-2") do
            i(class: "ph ph-broadcast")
            plain "Neural Link Output"
          end
          h2(class: "text-2xl font-light text-emerald-400 mt-2") { "Global Telemetry Stream" }
        end

        div(class: "flex items-center gap-3 bg-emerald-950/30 px-4 py-2 border border-emerald-900 shadow-[inset_0_0_10px_rgba(6,78,59,0.5)]") do
          div(class: "relative flex h-2 w-2") do
            span(class: "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75")
            span(class: "relative inline-flex rounded-full h-2 w-2 bg-emerald-500")
          end
          span(class: "font-mono text-mini text-emerald-500 uppercase tracking-widest") { "Carrier: Direct-to-Cell" }
        end
      end
    end
  end
end

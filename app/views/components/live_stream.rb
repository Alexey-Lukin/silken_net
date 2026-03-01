module Views
  module Components
    module Telemetry
      class LiveStream < ApplicationComponent
        def view_template
          div(class: "space-y-6 animate-in fade-in duration-1000") do
            header_section
            
            # Підписка на SolidCable
            turbo_stream_from "telemetry_stream"
            
            div(class: "relative border border-emerald-900 bg-black min-h-[600px] overflow-hidden") do
              # Ефект "Матриці" на фоні
              div(class: "absolute inset-0 opacity-5 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]")
              
              table(class: "w-full text-left font-mono text-[10px] relative z-10") do
                thead(class: "bg-emerald-950/30 text-emerald-700 uppercase tracking-widest") do
                  tr do
                    th(class: "p-3 w-32") { "Timestamp" }
                    th(class: "p-3 w-40") { "Source DID" }
                    th(class: "p-3") { "Raw Payload (Hex Bytes)" }
                    th(class: "p-3 w-24 text-right") { "Status" }
                  end
                end
                # Сюди Turbo Stream буде вставляти нові рядки (prepend)
                tbody(id: "telemetry_feed", class: "divide-y divide-emerald-900/20") do
                  tr(id: "feed_placeholder") do
                    td(colspan: 4, class: "p-10 text-center text-emerald-900 italic animate-pulse") do
                      "Waiting for Starlink uplink... Listening on CoAP port 5683..."
                    end
                  end
                end
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-center") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Neural Link Output" }
              h2(class: "text-2xl font-light text-emerald-400 mt-1") { "Global Telemetry Stream" }
            end
            div(class: "flex items-center space-x-3 bg-emerald-950/20 px-4 py-2 border border-emerald-900") do
              div(class: "h-2 w-2 rounded-full bg-emerald-500 animate-ping")
              span(class: "font-mono text-[10px] text-emerald-500 uppercase") { "Carrier: Direct-to-Cell via Starlink" }
            end
          end
        end
      end
    end
  end
end

module Views
  module Components
    module Telemetry
      class LogEntry < ApplicationComponent
        def initialize(packet:)
          @packet = packet
        end

        def view_template
          tr(class: "hover:bg-emerald-950/10 transition-colors animate-in slide-in-from-left duration-300") do
            td(class: "p-3 text-gray-600") { Time.current.strftime("%H:%M:%S.%L") }
            td(class: "p-3 text-emerald-500 font-bold") { @packet.device_did || "UNKNOWN" }
            td(class: "p-3 text-emerald-100 break-all leading-tight text-[9px]") do
              # Вивід сирих байтів у HEX
              @packet.payload_hex
            end
            td(class: "p-3 text-right") do
              span(class: "px-2 py-0.5 border border-emerald-900 text-[8px] text-emerald-700") { "DECRYPTED" }
            end
          end
        end
      end
    end
  end
end

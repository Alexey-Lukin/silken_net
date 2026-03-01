# app/views/components/telemetry/log_entry.rb
module Views
  module Components
    module Telemetry
      class LogEntry < ApplicationComponent
        def initialize(gateway:, hex_payload:, timestamp:)
          @gateway = gateway
          @hex_payload = hex_payload
          @timestamp = timestamp
        end

        def view_template
          tr(class: "hover:bg-emerald-950/10 border-b border-emerald-900/10 animate-in slide-in-from-left duration-300 group") do
            # Час з мілісекундами для відчуття швидкості
            td(class: "p-3 text-gray-600 font-mono text-[9px]") { @timestamp.strftime("%H:%M:%S.%L") }
            
            # Джерело (Королева)
            td(class: "p-3") do
              span(class: "text-emerald-500 font-bold") { @gateway&.uid || "UNKNOWN_RELAY" }
              span(class: "ml-2 text-[8px] text-emerald-900") { "IP: #{@gateway&.ip_address || '?.?.?.?'}" }
            end
            
            # Сирий потік байтів
            td(class: "p-3 font-mono text-emerald-100/80 break-all leading-tight text-[9px] tracking-tighter") do
              @hex_payload
            end
            
            # Статус розшифрування
            td(class: "p-3 text-right text-[8px] uppercase tracking-widest") do
              span(class: "px-2 py-0.5 border border-emerald-900 text-emerald-700 group-hover:text-emerald-400 group-hover:border-emerald-500 transition-colors") do
                "BATCH_RECEIVED"
              end
            end
          end
        end
      end
    end
  end
end

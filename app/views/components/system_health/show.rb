# frozen_string_literal: true

module SystemHealth
  class Show < ApplicationComponent
    def initialize(health:)
      @health = health
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-500") do
        header_section
        overall_status_banner
        div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
          render_coap_card
          render_sidekiq_card
          render_database_card
        end
        render_sidekiq_queues if @health[:sidekiq].is_a?(Hash) && @health[:sidekiq][:queues].present?
        render_footer
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "💓 System Health — Pulse Monitor" }
          p(class: "text-xs text-gray-600 mt-1") { "Статус CoAP listener, черг Sidekiq та з'єднання з базою даних." }
        end
        div(class: "flex items-center space-x-2") do
          div(class: tokens("h-2 w-2 rounded-full", all_healthy? ? "bg-emerald-500 shadow-[0_0_8px_#10b981]" : "bg-red-500 animate-pulse"))
          span(class: tokens("text-[9px] uppercase font-bold", all_healthy? ? "text-emerald-500" : "text-red-500")) { all_healthy? ? "ALL SYSTEMS GO" : "DEGRADED" }
        end
      end
    end

    def overall_status_banner
      if all_healthy?
        div(class: "border border-emerald-900 bg-emerald-950/20 p-4") do
          p(class: "text-emerald-500 text-xs font-mono uppercase tracking-widest") do
            "✓ ALL SUBSYSTEMS OPERATIONAL — Checked #{@health[:checked_at]}"
          end
        end
      else
        div(class: "border border-red-700 bg-red-950/30 p-4") do
          p(class: "text-red-400 text-xs font-mono font-bold uppercase tracking-widest") do
            "🚨 SYSTEM DEGRADED — One or more subsystems require attention"
          end
        end
      end
    end

    def render_coap_card
      coap = @health[:coap_listener] || {}
      alive = coap[:alive]

      service_card("CoAP Listener", alive) do
        div(class: "space-y-2 font-mono text-[10px]") do
          meta_row("Port", coap[:port] || "5683")
          meta_row("Protocol", "UDP / RFC 7252")
          meta_row("Status", alive ? "LISTENING" : "OFFLINE")
          if coap[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-[9px] text-red-400") { coap[:error] }
            end
          end
        end
      end
    end

    def render_sidekiq_card
      sidekiq = @health[:sidekiq] || {}
      healthy = sidekiq[:error].blank?

      service_card("Sidekiq Workers", healthy) do
        div(class: "space-y-2 font-mono text-[10px]") do
          meta_row("Enqueued", sidekiq[:enqueued] || "—")
          meta_row("Processed", sidekiq[:processed] || "—")
          meta_row("Failed", sidekiq[:failed] || "—")
          meta_row("Active Workers", sidekiq[:workers_size] || "—")
          if sidekiq[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-[9px] text-red-400") { sidekiq[:error] }
            end
          end
        end
      end
    end

    def render_database_card
      db = @health[:database] || {}
      connected = db[:connected]

      service_card("PostgreSQL", connected) do
        div(class: "space-y-2 font-mono text-[10px]") do
          meta_row("Engine", "PostgreSQL")
          meta_row("Connection", connected ? "ACTIVE" : "DISCONNECTED")
          if db[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-[9px] text-red-400") { db[:error] }
            end
          end
        end
      end
    end

    def service_card(name, healthy, &block)
      div(class: "p-6 border border-emerald-900 bg-black") do
        div(class: "flex justify-between items-start mb-6") do
          h4(class: "text-sm font-light text-emerald-100") { name }
          div(class: "flex items-center space-x-2") do
            div(class: tokens("h-1.5 w-1.5 rounded-full", healthy ? "bg-emerald-500 shadow-[0_0_6px_#10b981]" : "bg-red-500 animate-pulse"))
            span(class: tokens("text-[9px] uppercase font-bold", healthy ? "text-emerald-500" : "text-red-500")) { healthy ? "OK" : "DOWN" }
          end
        end
        yield
      end
    end

    def render_sidekiq_queues
      queues = @health[:sidekiq][:queues]

      div(class: "space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Sidekiq Queue Distribution" }
        div(class: "border border-emerald-900 bg-black overflow-hidden") do
          table(class: "w-full text-left font-mono text-[11px]") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
              tr do
                th(class: "p-4") { "Queue Name" }
                th(class: "p-4 text-right") { "Jobs Enqueued" }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              queues.each do |queue_name, count|
                tr(class: "hover:bg-emerald-950/10") do
                  td(class: "p-4 text-emerald-500") { queue_name.to_s }
                  td(class: "p-4 text-right text-gray-300") { count.to_s }
                end
              end
            end
          end
        end
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between items-center") do
        span(class: "text-gray-600 uppercase") { label }
        span(class: "text-emerald-400") { value.to_s }
      end
    end

    def render_footer
      div(class: "text-[9px] text-gray-600 text-right mt-2 font-mono") do
        "Last checked at #{@health[:checked_at]}"
      end
    end

    def all_healthy?
      coap_ok = @health.dig(:coap_listener, :alive) == true
      sidekiq_ok = @health[:sidekiq].is_a?(Hash) && @health[:sidekiq][:error].blank?
      db_ok = @health.dig(:database, :connected) == true
      coap_ok && sidekiq_ok && db_ok
    end
  end
end

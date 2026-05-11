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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t("system_health.show.title") }
          p(class: "text-xs text-gray-600 mt-1") { t("system_health.show.subtitle") }
        end
        div(class: "flex items-center gap-2") do
          div(class: tokens("h-2 w-2 rounded-full", "bg-emerald-500 shadow-[0_0_8px_#10b981]": all_healthy?, "bg-red-500 animate-pulse": !all_healthy?))
          span(class: tokens("text-mini uppercase font-bold", "text-emerald-500": all_healthy?, "text-red-500": !all_healthy?)) { all_healthy? ? t("system_health.show.all_systems_go") : t("system_health.show.degraded") }
        end
      end
    end

    def overall_status_banner
      if all_healthy?
        div(class: "border border-emerald-900 bg-emerald-950/20 p-4") do
          p(class: "text-emerald-500 text-xs font-mono uppercase tracking-widest") do
            t("system_health.show.all_operational", at: @health[:checked_at])
          end
        end
      else
        div(class: "border border-red-700 bg-red-950/30 p-4") do
          p(class: "text-red-400 text-xs font-mono font-bold uppercase tracking-widest") do
            t("system_health.show.system_degraded")
          end
        end
      end
    end

    def render_coap_card
      coap = @health[:coap_listener] || {}
      alive = coap[:alive]

      service_card(t("system_health.show.coap.name"), alive) do
        div(class: "space-y-2 font-mono text-tiny") do
          meta_row(t("system_health.show.coap.port"), coap[:port] || "5683")
          meta_row(t("system_health.show.coap.protocol"), t("system_health.show.coap.protocol_value"))
          meta_row(t("system_health.show.coap.status"), alive ? t("system_health.show.coap.listening") : t("system_health.show.coap.offline"))
          if coap[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-mini text-red-400") { coap[:error] }
            end
          end
        end
      end
    end

    def render_sidekiq_card
      sidekiq = @health[:sidekiq] || {}
      healthy = sidekiq[:error].blank?

      service_card(t("system_health.show.sidekiq.name"), healthy) do
        div(class: "space-y-2 font-mono text-tiny") do
          meta_row(t("system_health.show.sidekiq.enqueued"), sidekiq[:enqueued] || "—")
          meta_row(t("system_health.show.sidekiq.processed"), sidekiq[:processed] || "—")
          meta_row(t("system_health.show.sidekiq.failed"), sidekiq[:failed] || "—")
          meta_row(t("system_health.show.sidekiq.active_workers"), sidekiq[:workers_size] || "—")
          if sidekiq[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-mini text-red-400") { sidekiq[:error] }
            end
          end
        end
      end
    end

    def render_database_card
      db = @health[:database] || {}
      connected = db[:connected]

      service_card(t("system_health.show.database.name"), connected) do
        div(class: "space-y-2 font-mono text-tiny") do
          meta_row(t("system_health.show.database.engine"), t("system_health.show.database.engine_value"))
          meta_row(t("system_health.show.database.connection"), connected ? t("system_health.show.database.active") : t("system_health.show.database.disconnected"))
          if db[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-mini text-red-400") { db[:error] }
            end
          end
        end
      end
    end

    def service_card(name, healthy, &block)
      div(class: "p-6 border border-emerald-900 bg-black") do
        div(class: "flex justify-between items-start mb-6") do
          h4(class: "text-sm font-light text-emerald-100") { name }
          div(class: "flex items-center gap-2") do
            div(class: tokens("h-1.5 w-1.5 rounded-full", "bg-emerald-500 shadow-[0_0_6px_#10b981]": healthy, "bg-red-500 animate-pulse": !healthy))
            span(class: tokens("text-mini uppercase font-bold", "text-emerald-500": healthy, "text-red-500": !healthy)) { healthy ? t("system_health.show.status.ok") : t("system_health.show.status.down") }
          end
        end
        yield
      end
    end

    def render_sidekiq_queues
      queues = @health[:sidekiq][:queues]

      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("system_health.show.sidekiq.queues_title") }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t("system_health.show.sidekiq.queue_name") }
                th(scope: "col", class: "p-4 text-right") { t("system_health.show.sidekiq.jobs_enqueued") }
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
      div(class: "text-mini text-gray-600 text-right mt-2 font-mono") do
        t("system_health.show.last_checked", at: @health[:checked_at])
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

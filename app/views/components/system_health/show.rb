# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SystemHealth
  class Show < ApplicationComponent
    # [ARCH.81] Тон картки має ТРИ значення, а не два. «Не сконфігуровано» — це
    # не «мертвий»: якби вони світились однаково, панель знову навчала б
    # ігнорувати червоне, лише поверхом вище за саму пробу.
    COAP_TONES = {
      "alive" => :ok,
      "unreachable" => :down,
      "wire_mismatch" => :down,
      "check_failed" => :down,
      "not_configured" => :unknown
    }.freeze

    def initialize(health:)
      @health = health
    end

    def view_template
      div(class: "space-y-8") do
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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".title") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
        div(class: "flex items-center gap-2") do
          div(class: tokens("h-2 w-2 rounded-full", dot_class(overall_tone)))
          span(class: tokens("text-mini uppercase font-bold", text_class(overall_tone))) { overall_headline }
        end
      end
    end

    # Три банери, бо станів три. Зливати «не знаю» з «мертво» означало б
    # повернути на цю поверхню рівно той дефект, що жив у пробі.
    def overall_status_banner
      case overall_tone
      when :ok
        banner("border-emerald-900 bg-emerald-950/20", "text-emerald-500") { t(".all_operational", at: @health[:checked_at]) }
      when :unknown
        banner("border-amber-800 bg-amber-950/20", "text-amber-400") { t(".system_incomplete") }
      else
        banner("border-red-700 bg-red-950/30", "text-red-400") { t(".system_degraded") }
      end
    end

    def banner(box_classes, text_classes)
      div(class: tokens("p-4 border", box_classes)) do
        p(class: tokens("text-xs font-mono font-bold uppercase tracking-widest", text_classes)) { yield }
      end
    end

    def render_coap_card
      coap = @health[:coap_listener] || {}

      service_card(t(".coap.name"), coap_tone) do
        div(class: "space-y-2 font-mono text-tiny") do
          # Адреса тут не косметика: демон живе поза цим процесом, тож без неї
          # неможливо сказати, ЩО саме пробували дістати.
          meta_row(t(".coap.host"), coap[:host] || t(".coap.host_unset"))
          meta_row(t(".coap.port"), coap[:port])
          meta_row(t(".coap.protocol"), t(".coap.protocol_value"))
          meta_row(t(".coap.status"), t(".coap.states.#{coap[:status]}", default: t(".coap.states.check_failed")))
        end
      end
    end

    def render_sidekiq_card
      sidekiq = @health[:sidekiq] || {}

      service_card(t(".sidekiq.name"), sidekiq_tone) do
        div(class: "space-y-2 font-mono text-tiny") do
          # Число процесів стоїть першим свідомо: воно і є відповідь на питання,
          # яке ставить ім'я картки. Решта — лічильники з Redis.
          meta_row(t(".sidekiq.processes"), sidekiq[:processes] || "—")
          meta_row(t(".sidekiq.enqueued"), sidekiq[:enqueued] || "—")
          meta_row(t(".sidekiq.processed"), sidekiq[:processed] || "—")
          meta_row(t(".sidekiq.failed"), sidekiq[:failed] || "—")
          meta_row(t(".sidekiq.active_workers"), sidekiq[:workers_size] || "—")
          if sidekiq[:error]
            div(class: "mt-2 p-2 border border-red-900/30 bg-red-950/10") do
              p(class: "text-mini text-red-400") { sidekiq[:error] }
            end
          end
        end
      end
    end

    def render_database_card
      connected = database_connected?

      service_card(t(".database.name"), database_tone) do
        div(class: "space-y-2 font-mono text-tiny") do
          meta_row(t(".database.engine"), t(".database.engine_value"))
          meta_row(t(".database.connection"), connected ? t(".database.active") : t(".database.disconnected"))
        end
      end
    end

    def service_card(name, tone, &block)
      div(class: "p-6 border border-emerald-900 bg-black") do
        div(class: "flex justify-between items-start mb-6") do
          h4(class: "text-sm font-light text-emerald-100") { name }
          div(class: "flex items-center gap-2") do
            div(class: tokens("h-1.5 w-1.5 rounded-full", dot_class(tone)))
            span(class: tokens("text-mini uppercase font-bold", text_class(tone))) { t(".status.#{tone}") }
          end
        end
        yield
      end
    end

    def render_sidekiq_queues
      queues = @health[:sidekiq][:queues]

      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".sidekiq.queues_title") }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".sidekiq.queue_name") }
                th(scope: "col", class: "p-4 text-right") { t(".sidekiq.jobs_enqueued") }
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
        t(".last_checked", at: @health[:checked_at])
      end
    end

    def coap_tone
      COAP_TONES.fetch(@health.dig(:coap_listener, :status).to_s, :down)
    end

    def sidekiq_tone
      @health.dig(:sidekiq, :alive) == true ? :ok : :down
    end

    def database_tone
      database_connected? ? :ok : :down
    end

    def database_connected?
      @health.dig(:database, :connected) == true
    end

    # Найгірший тон виграє — але «не знаю» ніколи не стає «все добре»:
    # неповний вимір це власний стан, а не різновид успіху.
    def overall_tone
      tones = [ coap_tone, sidekiq_tone, database_tone ]
      return :down if tones.include?(:down)
      return :unknown if tones.include?(:unknown)

      :ok
    end

    def overall_headline
      case overall_tone
      when :ok      then t(".all_systems_go")
      when :unknown then t(".incomplete")
      else               t(".degraded")
      end
    end

    # Класи тіні лишаються ЛІТЕРАЛАМИ: Tailwind v4 шукає їх скануванням джерела,
    # тож зібраний інтерполяцією `shadow-[…]` просто не згенерувався б.
    # [UI.1] Радіуси glow зведені до 8px по всьому дереву — kwarg `large:` пішов разом із 6px.
    def dot_class(tone)
      case tone
      when :ok      then "bg-gaia-primary-strong shadow-[0_0_8px_#10b981]"
      when :unknown then "bg-status-warning-accent"
      else               "bg-status-danger-accent animate-pulse"
      end
    end

    def text_class(tone)
      case tone
      when :ok      then "text-emerald-500"
      when :unknown then "text-amber-500"
      else               "text-red-500"
      end
    end
  end
end

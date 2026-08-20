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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".title") }
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
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
        banner("border-gaia-border bg-gaia-surface-sunken", "text-gaia-primary-strong") { t(".all_operational", at: @health[:checked_at]) }
      when :unknown
        banner("border-status-warning-accent bg-status-warning/10", "text-status-warning-accent") { t(".system_incomplete") }
      else
        banner("border-status-danger-accent bg-status-danger/10", "text-status-danger-accent") { t(".system_degraded") }
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
            div(class: "mt-2 p-2 border border-status-danger-accent/30 bg-status-danger/10") do
              p(class: "text-mini text-status-danger-accent") { sidekiq[:error] }
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
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        div(class: "flex justify-between items-start mb-6") do
          h4(class: "text-sm font-light text-gaia-text-strong") { name }
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
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".sidekiq.queues_title") }
        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".sidekiq.queue_name") }
                th(scope: "col", class: "p-4 text-right") { t(".sidekiq.jobs_enqueued") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              queues.each do |queue_name, count|
                tr(class: "hover:bg-gaia-surface-sunken") do
                  td(class: "p-4 text-gaia-primary-strong") { queue_name.to_s }
                  td(class: "p-4 text-right text-gaia-text-subtle") { count.to_s }
                end
              end
            end
          end
        end
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between items-center") do
        span(class: "text-gaia-text-muted uppercase") { label }
        span(class: "text-gaia-text") { value.to_s }
      end
    end

    def render_footer
      div(class: "text-mini text-gaia-text-muted text-right mt-2 font-mono") do
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
      when :ok      then "text-gaia-primary-strong"
      when :unknown then "text-status-warning-accent"
      else               "text-status-danger-accent"
      end
    end
  end
end

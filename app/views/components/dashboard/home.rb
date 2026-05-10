# frozen_string_literal: true

module Dashboard
  class Home < ApplicationComponent
    # Default Citadel coordinates shown over the geo matrix until the map
    # tiles load. Sourced from the project HQ in Cherkasy, UA.
    DEFAULT_COORDINATES = { lat: "49.4447", lon: "32.0588", alt: "112" }.freeze

    def initialize(stats:, events:)
      @stats = stats
      @events = events
    end

    def view_template
      div(class: "space-y-10 animate-in fade-in duration-1000") do
        # Ряд головних метрик (The Four Pillars)
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
          render Views::Shared::UI::StatCard.new(label: t_("stats.forest_vitality"), value: "#{@stats[:trees][:health_avg].to_i}%")
          render Views::Shared::UI::StatCard.new(label: t_("stats.active_soldiers"), value: @stats[:trees][:active], sub: "/ #{@stats[:trees][:total]}")
          render Views::Shared::UI::StatCard.new(label: t_("stats.carbon_treasury"), value: @stats[:economy][:total_scc], sub: "SCC")
          render Views::Shared::UI::StatCard.new(
            label: t_("stats.ionic_potential"),
            value: "#{@stats[:energy][:avg_voltage]}mV",
            danger: @stats[:energy][:avg_voltage] < 3300
          )
        end

        # Центральна секція: Карта та Алерти
        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          render_geospatial_matrix
          render_live_feed
        end
      end
    end

    private

    # Lazy-lookup helper scoped to the `dashboard.home.*` namespace.
    def t_(key) = I18n.t("dashboard.home.#{key}")

    def render_geospatial_matrix
      div(class: "lg:col-span-2 p-1 border border-gaia-border bg-gaia-surface h-[500px] relative group overflow-hidden") do
        # Фоновий растр — декоративний бренд-акцент.
        div(class: "absolute inset-0 bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:30px_30px] opacity-10", aria_hidden: "true")

        div(class: "absolute inset-0 flex flex-col items-center justify-center gap-4") do
          div(class: "h-12 w-12 border-2 border-emerald-500/20 border-t-emerald-500 rounded-full animate-spin", aria_hidden: "true")
          p(class: "text-gaia-text-subtle font-mono text-tiny uppercase tracking-[0.5em]") { t_("map.loading") }
        end

        # Overlay для координат
        div(class: "absolute bottom-4 left-4 font-mono text-micro text-gaia-text-subtle") do
          I18n.t("dashboard.home.map.coordinates_label", **DEFAULT_COORDINATES)
        end
      end
    end

    def render_live_feed
      div(class: "p-6 border border-gaia-border bg-gaia-surface-elevated flex flex-col h-full") do
        div(class: "flex justify-between items-center mb-8") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t_("feed.title") }
          div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping", aria_hidden: "true")
        end

        div(class: "flex-1 flex flex-col gap-6 overflow-y-auto pr-2 custom-scrollbar") do
          @events.each { |event| render Dashboard::EventRow.new(event: event) }
        end

        a(
          href: api_v1_alerts_path,
          class: "mt-8 text-center py-2 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
                 "hover:text-gaia-text hover:border-gaia-border-strong transition-all " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
        ) { t_("feed.view_all") }
      end
    end
  end
end

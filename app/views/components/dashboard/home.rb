# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class Home < ApplicationComponent
    def initialize(stats:, events:, trees:, organization:)
      @stats = stats
      @events = events
      @trees = trees
      @organization = organization
    end

    def view_template
      div(class: "space-y-10 animate-in fade-in duration-1000") do
        # Ряд головних метрик (The Four Pillars)
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
          # `health_avg` — середнє `health_index`, шкала 0..1 (`04_01 §3`). Доти тут
          # стояло `.to_i`, тобто 0.92 → **0**: здорова організація бачила «0%»
          # життєздатності на головній сторінці. Переведення у відсоток робить в'ю —
          # так само, як `clusters/show`, `clusters/item`, `organizations/show`,
          # `contracts/show`.
          render Views::Shared::UI::StatCard.new(label: t(".stats.forest_vitality"), value: "#{(@stats[:trees][:health_avg].to_f * 100).round}%")
          render Views::Shared::UI::StatCard.new(label: t(".stats.active_soldiers"), value: @stats[:trees][:active], sub: "/ #{@stats[:trees][:total]}")
          render Views::Shared::UI::StatCard.new(label: t(".stats.carbon_treasury"), value: @stats[:economy][:total_scc], sub: "SCC")
          render Views::Shared::UI::StatCard.new(
            label: t(".stats.ionic_potential"),
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

    # Обгортка несе ЛИШЕ позицію в сітці: рамку, висоту й фон тримає сам
    # `Dashboard::Map`, інакше вийшла б рамка в рамці й подвійні 500px.
    def render_geospatial_matrix
      div(class: "lg:col-span-2") do
        render Dashboard::Map.new(trees: @trees, organization: @organization)
      end
    end

    def render_live_feed
      div(class: "p-6 border border-gaia-border bg-gaia-surface-elevated flex flex-col h-full") do
        div(class: "flex justify-between items-center mb-8") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".feed.title") }
          div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping", aria_hidden: "true")
        end

        div(class: "flex-1 flex flex-col gap-6 overflow-y-auto pr-2 custom-scrollbar") do
          if @events.empty?
            p(class: "text-gaia-text-subtle font-mono text-tiny uppercase tracking-widest text-center py-8") { t(".feed.empty") }
          else
            @events.each { |event| render Dashboard::EventRow.new(event: event) }
          end
        end

        a(
          href: api_v1_alerts_path,
          class: "mt-8 text-center py-2 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
                 "hover:text-gaia-text hover:border-gaia-border-strong transition-all " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
        ) { t(".feed.view_all") }
      end
    end
  end
end

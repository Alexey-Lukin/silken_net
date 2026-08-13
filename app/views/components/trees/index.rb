# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Trees
  class Index < ApplicationComponent
    def initialize(cluster:, trees:, pagy: nil)
      @cluster = cluster
      @trees = trees
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        # Масова сітка солдатів
        div(class: "grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4") do
          @trees.each do |tree|
            render_soldier_node(tree)
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { cluster_trees_path(@cluster, page: page) }
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex flex-col sm:flex-row sm:justify-between sm:items-end gap-4 mb-6 border-b border-gaia-border pb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted") { t(".eyebrow") }
          h2(class: "text-3xl font-extralight text-gaia-text mt-1") { @cluster.name }
        end

        div(class: "flex gap-8 text-right font-mono text-tiny") do
          header_stat(t(".header_population"), @pagy&.count || @trees.size, t(".header_population_unit"))
          header_stat(t(".header_operational"), @cluster.active_trees_count, t(".header_operational_unit"))
        end
      end
    end

    def header_stat(label, value, unit, danger: false)
      div do
        p(class: "text-gaia-text-muted uppercase mb-1") { label }
        span(class: tokens("text-lg", "text-status-danger-text": danger, "text-gaia-text-strong": !danger)) { value.to_s }
        span(class: "ml-1 text-gaia-text-subtle") { unit }
      end
    end

    def render_soldier_node(tree)
      voltage = tree.supply_voltage_mv
      charge_percent = tree.charge_percentage

      a(
        href: tree_path(tree),
        class: "group relative p-3 border border-gaia-border-strong bg-gaia-surface hover:border-gaia-primary transition-all duration-300"
      ) do
        # DID та Статус
        div(class: "flex justify-between items-start mb-3") do
          div do
            span(class: "text-mini font-mono text-gaia-text-subtle group-hover:text-gaia-text") { tree.did.last(6) }
            span(class: "ml-1") { render Views::Shared::UI::StatusBadge.new(status: tree.status) }
          end
          div(class: tokens("h-1.5 w-1.5 rounded-full", tree_status_led(tree)))
        end

        # [ARCH.99] Смуга рахує ВІДСОТОК від `voltage`, а `voltage` — це мВ VDDA
        # (шина живлення MCU), не заряд іоністора: Vcap-каналу на вузлі нема (`03_01` FW.50).
        # ⚠️ Сама шкала лишається відкритим ⚖️ — здорова 3.3 V шина дає тут ~17 %.
        div(class: "space-y-1") do
          div(class: "flex justify-between text-micro uppercase text-gaia-text font-mono") do
            span { t(".supply_voltage") }
            span { "#{voltage}mV" }
          end
          div(class: "w-full h-0.5 bg-gaia-surface-sunken overflow-hidden") do
            div(
              class: tokens("h-full transition-all duration-1000", charge_color(charge_percent)),
              style: "width: #{charge_percent}%"
            )
          end
        end

        # Hover overlay зі стресом
        div(class: "absolute inset-0 bg-emerald-500/10 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none")
      end
    end

    def tree_status_led(tree)
      return "bg-status-danger animate-pulse shadow-[0_0_8px_red]" if tree.under_threat?
      return "bg-gaia-text-subtle" if tree.last_seen_at.nil? || tree.last_seen_at < 24.hours.ago
      "bg-emerald-500 shadow-[0_0_5px_#10b981]"
    end

    def charge_color(percent)
      if percent > 70 then "bg-emerald-500 shadow-[0_0_5px_#10b981]"
      elsif percent > 30 then "bg-status-warning"
      else "bg-status-danger animate-pulse"
      end
    end
  end
end

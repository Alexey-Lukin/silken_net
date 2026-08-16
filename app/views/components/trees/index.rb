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
      div(class: "space-y-8") do
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

        # ⛔ [ARCH.99] Смуги «заряду» тут БІЛЬШЕ НЕМА: вона рахувала відсоток від
        # мВ VDDA — стабілізованої шини, що про запас енергії не каже нічого
        # (`02_03 §7`). Лишається сама напруга: чесна діагностика просідання.
        # Стан енергії читається з LED вище — тиша, а не вигадана шкала.
        div(class: "flex justify-between text-micro uppercase text-gaia-text font-mono") do
          span { t(".supply_voltage") }
          # [ARCH.84] `measured_value`, а не інтерполяція: доти дерево, яке ніколи
          # не виходило в ефір, друкувало тут «0mV» — браунаут-грейд показник —
          # просто під LED, що чесно показує тишу. Дві відповіді на одну величину
          # в одному рядку; `trees/show` для неї ж уже казав «не виміряно».
          span { measured_value(voltage, "mV", space: false) }
        end

        # Hover overlay зі стресом
        div(class: "absolute inset-0 bg-emerald-500/10 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none")
      end
    end

    # [ARCH.99] Поріг тиші приходить із моделі (`Tree#fresh_signal?`) — доти тут
    # стояла рукописна копія «24 години», тобто друга відповідь на те саме питання.
    def tree_status_led(tree)
      return "bg-status-danger animate-pulse shadow-[0_0_8px_red]" if tree.under_threat?
      return "bg-gaia-text-subtle" unless tree.fresh_signal?
      "bg-emerald-500 shadow-[0_0_5px_#10b981]"
    end
  end
end

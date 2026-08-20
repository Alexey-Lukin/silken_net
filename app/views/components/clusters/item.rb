# SPDX-License-Identifier: AGPL-3.0-or-later
# app/views/components/clusters/item.rb
# frozen_string_literal: true

module Clusters
  class Item < ApplicationComponent
    def initialize(cluster:)
      @cluster = cluster
    end

    def view_template
      div(class: "group relative p-6 border border-gaia-border bg-gaia-surface hover:bg-gaia-surface-sunken transition-all duration-500") do
        header_section
        stats_section
        footer_section
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-start mb-6") do
        div do
          h3(class: "text-lg font-light tracking-widest text-gaia-text-strong uppercase") { @cluster.name }
          p(class: "text-tiny font-mono text-gaia-text-subtle") { t(".id", id: @cluster.id) }
        end

        # Статус кластера (на основі AI інсайтів або алертів).
        # 🔴 Предикат ЗАПИТУЄ БД (`ews_alerts.unresolved.critical.exists?`) і НЕ мемоїзується —
        # тож він читається рівно один раз на рендер. Це не мікрооптимізація: рядок їде в циклі
        # `Clusters::Grid`, тобто кожен зайвий виклик множиться на кількість кластерів. Свідомий
        # tradeoff контролера («EXISTS з composite index — `includes` не потрібен») рахований на
        # ОДИН запит на рядок, і саме цей рядок його таким тримає.
        threats = @cluster.active_threats?
        div(class: tokens(
          "h-2 w-2 rounded-full",
          "bg-red-500 animate-pulse": threats,
          "bg-emerald-500": !threats
        ))
      end
    end

    def stats_section
      div(class: "grid grid-cols-2 gap-4 mb-6") do
        stat_block(t(".trees"), @cluster.total_active_trees)
        stat_block(t(".health"), measured_percent(@cluster.health_index))
      end
    end

    def stat_block(label, value)
      div do
        p(class: "text-mini uppercase tracking-tighter text-gaia-text-muted") { label }
        p(class: "text-xl font-light text-gaia-text-strong") { value }
      end
    end

    def footer_section
      div(class: "flex justify-between items-center mt-4 pt-4 border-t border-gaia-border-strong") do
        # Кнопка переходу через Turbo (без рефрешу сторінки)
        a(
          href: cluster_path(@cluster),
          class: "text-tiny uppercase tracking-widest text-gaia-primary-strong hover:text-gaia-text-strong transition-colors " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
        ) { t(".open_matrix") }
      end
    end
  end
end

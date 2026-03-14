# app/views/components/clusters/item.rb
# frozen_string_literal: true

module Clusters
  class Item < ApplicationComponent
    def initialize(cluster:)
      @cluster = cluster
    end

    def view_template
      div(class: "group relative p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
        header_section
        stats_section
        footer_section
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-start mb-6") do
        div do
          h3(class: "text-lg font-light tracking-widest text-emerald-400 uppercase") { @cluster.name }
          p(class: "text-tiny font-mono text-emerald-800") { "ID: #{@cluster.id}" }
        end

        # Статус кластера (на основі AI інсайтів або алертів)
        div(class: tokens(
          "h-2 w-2 rounded-full",
          "bg-red-500 animate-pulse": @cluster.active_threats?,
          "bg-emerald-500": !@cluster.active_threats?
        ))
      end
    end

    def stats_section
      div(class: "grid grid-cols-2 gap-4 mb-6") do
        stat_block("Trees", @cluster.total_active_trees)
        stat_block("Health", "#{(@cluster.health_index * 100).round}%")
      end
    end

    def stat_block(label, value)
      div do
        p(class: "text-mini uppercase tracking-tighter text-gray-600") { label }
        p(class: "text-xl font-light text-emerald-100") { value }
      end
    end

    def footer_section
      div(class: "flex justify-between items-center mt-4 pt-4 border-t border-emerald-900/50") do
        # Кнопка переходу через Turbo (без рефрешу сторінки)
        a(
          href: api_v1_cluster_path(@cluster),
          class: "text-tiny uppercase tracking-widest text-emerald-600 hover:text-emerald-300 transition-colors"
        ) { "Open Matrix →" }
      end
    end
  end
end

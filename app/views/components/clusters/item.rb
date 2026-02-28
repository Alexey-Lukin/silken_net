# app/views/components/clusters/item.rb
# frozen_string_literal: true

module Views
  module Components
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
              p(class: "text-[10px] font-mono text-emerald-800") { "ID: #{@cluster.slug || @cluster.id}" }
            end
            
            # Статус кластера (на основі AI інсайтів або алертів)
            div(class: tokens(
              "h-2 w-2 rounded-full",
              @cluster.ews_alerts.active.any? ? "bg-red-500 animate-pulse" : "bg-emerald-500"
            ))
          end
        end

        def stats_section
          div(class: "grid grid-cols-2 gap-4 mb-6") do
            stat_block("Trees", @cluster.trees.count)
            stat_block("Health", "#{@cluster.health_score || 100}%")
          end
        end

        def stat_block(label, value)
          div do
            p(class: "text-[9px] uppercase tracking-tighter text-gray-600") { label }
            p(class: "text-xl font-light text-emerald-100") { value }
          end
        end

        def footer_section
          div(class: "flex justify-between items-center mt-4 pt-4 border-t border-emerald-900/50") do
            # Кнопка переходу через Turbo (без рефрешу сторінки)
            a(
              href: helpers.api_v1_cluster_path(@cluster),
              class: "text-[10px] uppercase tracking-widest text-emerald-600 hover:text-emerald-300 transition-colors"
            ) { "Open Matrix →" }
          end
        end
      end
    end
  end
end

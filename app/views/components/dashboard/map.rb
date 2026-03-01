# frozen_string_literal: true

module Views
  module Components
    module Dashboard
      class Map < ApplicationComponent
        def initialize(trees:)
          @trees = trees
        end

        def view_template
          # Підключаємо CSS Leaflet прямо тут для капсуляції
          link(rel: "stylesheet", href: "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css", crossorigin: "")

          div(class: "w-full h-[500px] border border-emerald-900 bg-black/50 rounded relative z-0 overflow-hidden shadow-[0_0_30px_rgba(6,78,59,0.2)]") do
            
            # Підписка на глобальний канал оновлення мапи
            turbo_stream_from "geospatial_matrix"

            # Основний контейнер карти з підключеним Stimulus
            div(data_controller: "map", class: "w-full h-full z-0") do
              # Прихований блок даних. Stimulus "зчитує" звідси.
              div(id: "map_data_nodes", class: "hidden") do
                @trees.each { |tree| render Views::Components::Dashboard::MapNode.new(tree: tree) }
              end
            end
            
            # Неоновий HUD
            div(class: "absolute top-4 left-4 z-[400] bg-black/80 border border-emerald-900 p-3 backdrop-blur-md pointer-events-none") do
              h3(class: "text-[10px] uppercase tracking-widest text-emerald-500 mb-1 flex items-center gap-2") do
                div(class: "w-2 h-2 rounded-full bg-emerald-500 animate-pulse")
                plain "Geospatial Matrix"
              end
              p(class: "text-[9px] text-gray-400 font-mono") { "Live Active Nodes: #{@trees.count}" }
            end
          end
        end
      end
    end
  end
end

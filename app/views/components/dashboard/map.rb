# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class Map < ApplicationComponent
    def initialize(trees:, organization:)
      @trees = trees
      @organization = organization
    end

    def view_template
      # Підключаємо CSS Leaflet прямо тут для капсуляції
      link(rel: "stylesheet", href: "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css", crossorigin: "")

      div(class: "w-full h-[500px] border border-gaia-border bg-gaia-surface relative z-0 overflow-hidden shadow-[0_0_30px_rgba(6,78,59,0.2)]") do
        # Підписка скоуплена організацією глядача: ім'я стріму детерміноване,
        # тож голий рядок посадив би весь застосунок в ОДИН канал і роздав
        # координати чужого флоту. Без організації підписки нема (fail-closed).
        turbo_stream_from "geospatial_matrix_org_#{@organization.id}" if @organization

        # Основний контейнер карти з підключеним Stimulus.
        # `turbo-permanent`: Leaflet будує свій DOM усередині цього вузла, а
        # сервер віддає його порожнім — тож morph-рефреш (увімкнений у layout
        # заради `broadcast_refresh_to`) вирізав би плитки й маркери, лишивши
        # контролер живим і без `connect()`, який міг би їх відновити.
        div(id: "geospatial_map_canvas", data: { controller: "map", turbo_permanent: "" }, class: "w-full h-full z-0") do
          # Прихований блок даних. Stimulus "зчитує" звідси.
          div(id: "map_data_nodes", class: "hidden") do
            @trees.each { |tree| render Dashboard::MapNode.new(tree: tree) }
          end
        end

        # Неоновий HUD
        div(class: "absolute top-4 left-4 z-[400] bg-black/80 border border-emerald-900 p-3 backdrop-blur-md pointer-events-none") do
          h3(class: "text-tiny uppercase tracking-widest text-emerald-500 mb-1 flex items-center gap-2") do
            div(class: "w-2 h-2 rounded-full bg-emerald-500 animate-pulse")
            plain t(".heading")
          end
          p(class: "text-mini text-gray-400 font-mono") { t(".live_nodes", count: @trees.count) }
        end
      end
    end
  end
end

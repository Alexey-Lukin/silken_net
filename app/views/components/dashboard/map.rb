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
        # ⚠️ `data-turbo-permanent` тут пробували й ЗНЯЛИ — він шкодив більше,
        # ніж рятував. Атрибут вмикається на будь-якому Turbo-рендері, не лише
        # на morph (`preservingPermanentElements`), а морф вимагає ще й
        # `action === "replace"` — тобто звичайний клік по «Dashboard» його не
        # дає. На такому візиті Turbo ПЕРЕСАДЖУЄ вузол → Stimulus кличе
        # `disconnect()` → той робить `replaceChildren()` і зносить разом із
        # плитками Leaflet ще й `#map_data_nodes` НИЖЧЕ, який рендерить сервер;
        # мапа лишається порожньою, а наступні `broadcast_replace` летять у
        # неіснуючі id. Дашборд refresh-сигналів не отримує, тож морфу тут
        # нема від чого захищати.
        div(id: "geospatial_map_canvas", data: { controller: "map" }, class: "w-full h-full z-0") do
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
          # `.size`, а не `.count`: колекція вже завантажена рендером вузлів
          # вище, тож `.count` слав би ДРУГИЙ SQL (обгорнутий COUNT) на кожен
          # показ дашборду.
          p(class: "text-mini text-gray-400 font-mono") { t(".live_nodes", count: @trees.size) }
        end
      end
    end
  end
end

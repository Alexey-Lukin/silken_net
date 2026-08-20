# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Grid do
  # [TEST.12] Реальний незбережений `Cluster`. Дві ланки, яких мок не мав:
  # `total_active_trees` — не поле, а читач КОЛОНКИ `active_trees_count` (лічильник-кеш),
  # тож фікстура тепер годує саме колонку; `health_index` на моделі має фолбек
  # (`read_attribute || 1.0`), тобто `nil` вона не віддає ніколи.
  # ⚠️ `active_threats?` лишається стабом НАВМИСНО — це запит у БД
  # (`ews_alerts.unresolved.critical.exists?`), а не дані запису.
  def build_cluster(id: 1, name: "Carpathian-Alpha", active_threats: false, total_active_trees: 42,
                    health_index: 0.85)
    cluster = Cluster.new(id: id, name: name, active_trees_count: total_active_trees,
                          health_index: health_index)
    allow(cluster).to receive(:active_threats?).and_return(active_threats)
    cluster
  end

  let(:clusters) { [ build_cluster(id: 1, name: "Carpathian-Alpha"), build_cluster(id: 2, name: "Danube-Beta") ] }
  let(:html)     { render_component(clusters: clusters, pagy: mock_pagy(count: 63)) }

  describe "grid layout" do
    it "renders a grid container" do
      expect(html).to include("grid")
    end

    it "renders each cluster item" do
      expect(html).to include("Carpathian-Alpha")
      expect(html).to include("Danube-Beta")
    end
  end

  describe "item delegation" do
    it "renders cluster ID" do
      expect(html).to include("ID: 1")
    end

    it "renders Open Matrix link" do
      expect(html).to include("Open Matrix")
    end

    it "renders health index as percentage" do
      expect(html).to include("85%")
    end

    it "renders tree count" do
      expect(html).to include("42")
    end
  end

  describe "LED status" do
    it "renders emerald LED when no active threats" do
      expect(html).to include("bg-gaia-primary-strong")
    end

    it "renders red LED when cluster has active threats" do
      threat_cluster = build_cluster(id: 3, name: "Threat-Cluster", active_threats: true)
      html = render_component(clusters: [ threat_cluster ], pagy: mock_pagy(count: 63))

      expect(html).to include("bg-status-danger-accent")
      # Другий бік несучий: сама присутність червоного лишається зеленою й тоді,
      # коли гілки рендеряться ОБИДВІ (у сітці з одним кластером інших LED немає).
      expect(html).not_to include("bg-gaia-primary-strong")
    end
  end

  describe "empty state" do
    it "renders empty state message when no clusters" do
      html = render_component(clusters: [], pagy: mock_pagy(count: 63))
      expect(html).to include("Matrix is empty")
    end
  end

  describe "pagination" do
    it "renders pagination links" do
      expect(html).to include("page=")
    end
  end
end

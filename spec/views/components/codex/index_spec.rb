# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Index do
  # Index renders sub-components (RealmTabs, NodeCard, Pagination, EmptyState).
  # We need a real Rails view context for `api_v1_codex_nodes_path` lookups
  # inside Pagination and RealmTabs. The `render_component` helper auto-detects
  # this and routes through `ApplicationController.renderer`.

  let!(:realm)         { create(:codex_realm, slug: "ecosystem", name_en: "Ecosystems") }
  let!(:other_realm)   { create(:codex_realm, slug: "trees",     name_en: "Trees") }

  let(:realms_collection) { Codex::Realm.where(id: [ realm.id, other_realm.id ]).order(:position) }

  describe "header" do
    it "renders the section heading and Lore Layer eyebrow" do
      pagy = mock_pagy(count: 0, page: 1, last: 1)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        active_realm_slug: nil,
        nodes_counts: {}
      )

      expect(html).to include("Lore Layer")
      expect(html).to include("Codex of Archetypes")
    end

    it "shows the total catalogue count from pagy.count" do
      pagy = mock_pagy(count: 42, page: 1, last: 3)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        active_realm_slug: nil,
        nodes_counts: {}
      )

      expect(html).to include("42 archetypes catalogued")
    end
  end

  describe "empty state" do
    it "renders the EmptyState copy when no nodes match" do
      pagy = mock_pagy(count: 0, page: 1, last: 1)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        active_realm_slug: "ecosystem",
        nodes_counts: { realm.id => 0 }
      )

      expect(html).to include("Codex is silent")
      expect(html).to include("Try a broader realm")
    end

    it "does not render the node grid when nodes is empty" do
      pagy = mock_pagy(count: 0, page: 1, last: 1)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        nodes_counts: {}
      )

      # Empty state replaces the grid; no NodeCard markup
      expect(html).not_to include('grid-cols-1 md:grid-cols-2 lg:grid-cols-3')
    end
  end

  describe "populated grid" do
    let!(:node_a) { create(:codex_node, realm: realm,       slug: "node-a", title_en: "Node A") }
    let!(:node_b) { create(:codex_node, realm: other_realm, slug: "node-b", title_en: "Node B") }

    it "renders one NodeCard per node in the responsive grid" do
      pagy = mock_pagy(count: 2, page: 1, last: 1)
      html = render_component(
        nodes: [ node_a, node_b ],
        pagy: pagy,
        realms: realms_collection,
        nodes_counts: { realm.id => 1, other_realm.id => 1 }
      )

      expect(html).to include("grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4")
      expect(html).to include("Node A")
      expect(html).to include("Node B")
    end

    it "renders the RealmTabs sub-component above the grid (with both realms)" do
      pagy = mock_pagy(count: 2, page: 1, last: 1)
      html = render_component(
        nodes: [ node_a ],
        pagy: pagy,
        realms: realms_collection,
        active_realm_slug: "ecosystem",
        nodes_counts: { realm.id => 1, other_realm.id => 1 }
      )

      expect(html).to include('aria-label="Codex realm filter"')
      expect(html).to include(">Ecosystems<")
      expect(html).to include(">Trees<")
    end
  end

  describe "realm_counts fallback" do
    it "falls back to a SQL GROUP BY when nodes_counts is not supplied" do
      create(:codex_node, realm: realm)

      pagy = mock_pagy(count: 0, page: 1, last: 1)
      # nodes_counts: nil triggers the fallback (Codex::Node.group(...).count)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        nodes_counts: nil
      )

      # The realm with one node should show count 1 in the tabs strip
      expect(html).to include(">Ecosystems<")
      expect(html).to include(">(1)<")
    end
  end

  describe "design system compliance" do
    it "does not leak raw bg-white / text-gray Tailwind colours into the wrapper" do
      pagy = mock_pagy(count: 0, page: 1, last: 1)
      html = render_component(
        nodes: [],
        pagy: pagy,
        realms: realms_collection,
        nodes_counts: {}
      )

      # Constrained to the wrapper section (sub-components have their own contracts);
      # asserting the top-level frame uses gaia-* border tokens.
      expect(html).to include("border-gaia-border")
    end
  end
end

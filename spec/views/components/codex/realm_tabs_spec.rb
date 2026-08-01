# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::RealmTabs do
  # The component uses `api_v1_codex_nodes_path` directly. We subclass the
  # component to inject a stub helper so the spec doesn't need a full
  # Rails request context (mirrors the pattern in
  # spec/views/components/codex/attunements/toggle_spec.rb).
  def render_tabs(realms:, nodes_counts: {}, active_realm_slug: nil)
    # [ARCH.77] Справжній renderer замість стабу маршрут-хелпера: той заморожував
    # адресу літералом, тож пін був твердженням про фікстуру, а не про роутер.
    render_component(
      realms: realms,
      nodes_counts: nodes_counts,
      active_realm_slug: active_realm_slug
    )
  end

  def mock_realm(id:, slug:, name_en:)
    OpenStruct.new(id: id, slug: slug, name_en: name_en)
  end

  let(:realm_eco)  { mock_realm(id: 1, slug: "ecosystem", name_en: "Ecosystems") }
  let(:realm_tree) { mock_realm(id: 2, slug: "trees",     name_en: "Trees") }
  let(:realms)     { [ realm_eco, realm_tree ] }
  let(:counts)     { { 1 => 12, 2 => 7 } }

  describe "rendering" do
    let(:html) { render_tabs(realms: realms, nodes_counts: counts) }

    it "renders an `All` tab whose count is the sum of all realm counts" do
      expect(html).to include(">All<")
      expect(html).to include(">(19)<") # 12 + 7
    end

    it "renders one tab per realm with its label and count" do
      expect(html).to include(">Ecosystems<")
      expect(html).to include(">Trees<")
      expect(html).to include(">(12)<")
      expect(html).to include(">(7)<")
    end

    it "links each tab to the filtered index using realm slug" do
      expect(html).to include('href="/api/v1/codex/nodes"')
      expect(html).to include('href="/api/v1/codex/nodes?realm=ecosystem"')
      expect(html).to include('href="/api/v1/codex/nodes?realm=trees"')
    end

    it "exposes a labelled <nav> for assistive tech" do
      expect(html).to match(/<nav[^>]+aria-label="Codex realm filter"/)
    end
  end

  describe "active state" do
    it "marks the matching realm tab as `aria-current=page` and applies active token classes" do
      html = render_tabs(realms: realms, nodes_counts: counts, active_realm_slug: "trees")
      # Find the <a> for the trees realm
      trees_anchor = html[/<a[^>]*href="\/api\/v1\/codex\/nodes\?realm=trees"[^>]*>/]
      expect(trees_anchor).to include('aria-current="page"')
      expect(trees_anchor).to include("border-gaia-primary")
      expect(trees_anchor).to include("text-gaia-primary")
    end

    it "marks the `All` tab as active when no realm slug is supplied" do
      html = render_tabs(realms: realms, nodes_counts: counts, active_realm_slug: nil)
      all_anchor = html[/<a[^>]*href="\/api\/v1\/codex\/nodes"[^>]*>/]
      expect(all_anchor).to include('aria-current="page"')
    end

    it "does not mark inactive tabs as `aria-current`" do
      html = render_tabs(realms: realms, nodes_counts: counts, active_realm_slug: "trees")
      eco_anchor = html[/<a[^>]*href="\/api\/v1\/codex\/nodes\?realm=ecosystem"[^>]*>/]
      expect(eco_anchor).not_to include('aria-current="page"')
      expect(eco_anchor).to include("text-gaia-text-muted")
    end
  end

  describe "edge cases" do
    it "renders gracefully with empty realms collection (only the All tab)" do
      html = render_tabs(realms: [], nodes_counts: {})
      expect(html).to include(">All<")
      expect(html).to include(">(0)<")
      expect(html.scan(/<a /).length).to eq(1)
    end

    it "shows 0 for realms missing from nodes_counts" do
      html = render_tabs(realms: realms, nodes_counts: { 1 => 5 }) # no entry for id=2
      expect(html).to include(">Ecosystems<")
      expect(html).to include(">Trees<")
      # Trees count should be 0; All sum should be 5
      expect(html).to include(">(5)<")
      expect(html).to include(">(0)<")
    end
  end

  describe "design system compliance" do
    let(:html) { render_tabs(realms: realms, nodes_counts: counts) }

    it "uses gaia-* tokens, not raw Tailwind colours" do
      expect(html).not_to include("bg-white")
      expect(html).not_to include("text-gray-")
      expect(html).not_to include("bg-red-")
    end

    it "applies focus-visible:ring-2 + focus-visible:ring-gaia-primary on every tab (a11y)" do
      anchors = html.scan(/<a [^>]+>/)
      expect(anchors).to all(include("focus-visible:ring-2"))
      expect(anchors).to all(include("focus-visible:ring-gaia-primary"))
    end
  end
end

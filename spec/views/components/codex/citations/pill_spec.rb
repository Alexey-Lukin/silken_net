# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Citations::Pill, type: :view_component do
  let(:node)     { create(:codex_node, slug: "mafusail", title_en: "Mafusail", archetype_key: "relict_oracle") }
  let(:citation) { create(:codex_citation, node: node, note: "centennial") }

  def render_pill(citation:)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
    end.new(citation: citation).call
  end

  it "renders a slug-href anchor with the title and archetype glyph" do
    html = render_pill(citation: citation)
    expect(html).to include("/api/v1/codex/nodes/mafusail")
    expect(html).to include("Mafusail")
    expect(html).to include("relict_oracle")
    expect(html).to include("codex_citation_#{citation.id}")
  end

  it "carries an aria_label that includes the note for hover tooling" do
    html = render_pill(citation: citation)
    expect(html).to match(/aria-label="[^"]*centennial/)
  end

  it "is a no-op when the node is nil (defensive)" do
    citation.node = nil
    html = render_pill(citation: citation)
    expect(html.to_s.strip).to be_empty
  end

  it "uses gaia-* tokens (no raw bg-white / text-gray)" do
    html = render_pill(citation: citation)
    expect(html).to include("bg-gaia-surface-sunken")
    expect(html).not_to include("bg-white")
    expect(html).not_to match(/text-gray-\d/)
  end

  it "exposes a focus-visible ring for accessibility" do
    html = render_pill(citation: citation)
    expect(html).to include("focus-visible:ring-2")
  end

  describe "title fallback" do
    it "uses the node slug as the label when title_en is blank" do
      allow(node).to receive(:title_en).and_return("")
      html = render_pill(citation: citation)
      expect(html).to include(">mafusail<")
    end
  end

  describe "archetype suffix" do
    it "omits the archetype chip when archetype_key is blank" do
      allow(node).to receive(:archetype_key).and_return(nil)
      html = render_pill(citation: citation)
      # `tracking-tighter` is unique to the archetype span; its absence
      # proves the `archetype_key.present?` else-branch was taken.
      expect(html).not_to include("tracking-tighter")
    end
  end

  describe "without a note" do
    before { citation.note = nil }

    it "builds an aria label without the trailing note clause" do
      html = render_pill(citation: citation)
      expect(html).to include('aria-label="Codex citation: Mafusail (Test Realm)"')
    end

    it "uses the bare title as the hover title attribute" do
      html = render_pill(citation: citation)
      expect(html).to include('title="Mafusail"')
    end
  end

  describe "realm-less node [coverage / defensive]" do
    before { allow(node).to receive(:realm).and_return(nil) }

    it "falls back to the neutral accent border and default glyph" do
      html = render_pill(citation: citation)
      expect(html).to include("border-l-gaia-border")
      expect(html).to include("○") # Codex::Realm::DEFAULT_DISPLAY_GLYPH
    end

    it "marks the realm as unknown in the aria label" do
      html = render_pill(citation: citation)
      expect(html).to match(/aria-label="[^"]*unknown realm/)
    end
  end
end

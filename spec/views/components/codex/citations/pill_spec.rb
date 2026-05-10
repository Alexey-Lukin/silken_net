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
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Citations::Strip, type: :view_component do
  let(:node) { create(:codex_node, slug: "mafusail", title_en: "Mafusail") }
  let(:tree) { create(:tree) }

  def render_strip(target:, citations:)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
    end.new(target: target, citations: citations).call
  end

  it "renders an empty-state when no citations attached" do
    html = render_strip(target: tree, citations: [])
    expect(html).to include("Untold.")
    expect(html).to include("codex_citations_tree_#{tree.id}")
    expect(html).to include('aria-live="polite"')
  end

  it "renders one Pill per citation" do
    citations = [ create(:codex_citation, node: node, citable_type: "Tree", citable_id: tree.id) ]
    html = render_strip(target: tree, citations: citations)
    expect(html).to include("Mafusail")
    expect(html).to include("/api/v1/codex/nodes/mafusail")
  end

  it "uses gaia-* tokens (no raw bg-white / text-gray) in the wrapper" do
    html = render_strip(target: tree, citations: [])
    expect(html).to include("text-gaia-text-muted")
    expect(html).not_to include("bg-white")
  end

  it "falls back to the target's class name for the DOM id when Codex::Citation is undefined" do
    hide_const("Codex::Citation")
    html = render_strip(target: tree, citations: [])
    expect(html).to include("codex_citations_tree_#{tree.id}")
  end

  it "renders multiple Pills in the given order for multiple citations" do
    other_node = create(:codex_node, slug: "cherkasy-bir", title_en: "Cherkasy Bir")
    citations = [
      create(:codex_citation, node: node, citable_type: "Tree", citable_id: tree.id),
      create(:codex_citation, node: other_node, citable_type: "Tree", citable_id: tree.id)
    ]
    html = render_strip(target: tree, citations: citations)
    expect(html).to include("Mafusail")
    expect(html).to include("Cherkasy Bir")
    expect(html.index("Mafusail")).to be < html.index("Cherkasy Bir")
  end

  it "marks the empty-state as a note landmark inside the additive live region" do
    html = render_strip(target: tree, citations: [])
    expect(html).to include('role="note"')
    expect(html).to include('aria-relevant="additions"')
  end

  it "treats a nil citations argument the same as an empty array" do
    html = render_strip(target: tree, citations: nil)
    expect(html).to include("Untold.")
  end

  it "derives a distinct DOM id per target instance, not a constant" do
    other_tree = create(:tree)
    html_a = render_strip(target: tree, citations: [])
    html_b = render_strip(target: other_tree, citations: [])
    expect(html_a).to include("codex_citations_tree_#{tree.id}")
    expect(html_b).to include("codex_citations_tree_#{other_tree.id}")
  end
end

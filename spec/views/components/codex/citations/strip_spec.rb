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
    expect(html).to include("No lore citations yet")
    expect(html).to include("codex_citations_tree_#{tree.id}")
  end

  it "renders one Pill per citation" do
    citations = [ create(:codex_citation, node: node, citable_type: "Tree", citable_id: tree.id) ]
    html = render_strip(target: tree, citations: citations)
    expect(html).to include("Mafusail")
    expect(html).to include("/api/v1/codex/nodes/mafusail")
  end

  it "uses gaia-* tokens (no raw bg-white / text-gray) in the wrapper" do
    html = render_strip(target: tree, citations: [])
    expect(html).to include("text-gaia-text-muted").or include("italic")
    expect(html).not_to include("bg-white")
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::CitationBlueprint do
  let(:node)    { create(:codex_node, slug: "mafusail", title_en: "Mafusail", archetype_key: "relict_oracle") }
  let(:user)    { create(:user) }
  let(:tree)    { create(:tree) }
  let(:citation) do
    create(:codex_citation,
           node: node,
           created_by_user: user,
           citable_type: "Tree",
           citable_id: tree.id,
           note: "centennial — see lore_md")
  end

  it "renders denormalised node fields for the pill renderer" do
    payload = described_class.render_as_hash(citation)
    expect(payload).to include(
      id:                  citation.id,
      codex_node_id:       node.id,
      citable_type:        "Tree",
      citable_id:          tree.id,
      note:                "centennial — see lore_md",
      created_by_user_id:  user.id,
      node_slug:           "mafusail",
      node_title_en:       "Mafusail",
      node_archetype_key:  "relict_oracle"
    )
  end

  it "tolerates a citation whose node is gone (defensive nil-safe)" do
    citation.node = nil
    payload = described_class.render_as_hash(citation)
    expect(payload[:node_slug]).to be_nil
    expect(payload[:node_title_en]).to be_nil
  end
end

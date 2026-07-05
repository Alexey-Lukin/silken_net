# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Leaderboard::Table, type: :view_component do
  let(:realm) { create(:codex_realm, name_en: "Mythos") }

  def render_table(**kwargs)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
    end.new(**kwargs).call
  end

  it "renders header, top-N caption and row data ordered as given" do
    n1 = create(:codex_node, realm: realm, title_en: "Apex",  attunement_elo: 1900, match_count: 50)
    n2 = create(:codex_node, realm: realm, title_en: "Mid",   attunement_elo: 1600, match_count: 20)
    html = render_table(realm: realm, nodes: [ n1, n2 ], limit: 25)

    expect(html).to include("Codex Leaderboard")
    expect(html).to include("Realm: Mythos")
    expect(html).to include("Top 25")
    expect(html).to include("Apex")
    expect(html).to include("1900")
    expect(html.index("Apex")).to be < html.index("Mid")
  end

  it "renders the empty-state copy when nodes are empty" do
    html = render_table(realm: realm, nodes: [], limit: 25)
    expect(html).to include("No ranked nodes yet.")
  end

  it "uses gaia-* tokens only" do
    html = render_table(realm: realm, nodes: [], limit: 10)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end

  it "omits the realm prefix when realm is nil" do
    html = render_table(realm: nil, nodes: [], limit: 10)
    expect(html).to include("Top 10")
    expect(html).not_to include("Realm:")
  end
end

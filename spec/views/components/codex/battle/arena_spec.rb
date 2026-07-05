# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Battle::Arena, type: :view_component do
  let(:realm) { create(:codex_realm) }
  let(:left)  { create(:codex_node, realm: realm, attunement_elo: 1550, match_count: 4) }
  let(:right) { create(:codex_node, realm: realm, attunement_elo: 1450, match_count: 7) }

  def render_arena(**kwargs)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_matches_path) { "/api/v1/codex/matches" }
    end.new(**kwargs).call
  end

  it "renders Arena frame, two cards with Elo & match counters, and hidden seed inputs" do
    html = render_arena(left: left, right: right, pair_seed: "deadbeef" * 8, realm: realm)
    expect(html).to include('id="codex_battle_arena"')
    expect(html).to include("VS")
    expect(html).to include(left.title_en)
    expect(html).to include(right.title_en)
    expect(html).to include("Elo: 1550")
    expect(html).to include("Elo: 1450")
    expect(html).to include('value="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"')
    expect(html).to include('action="/api/v1/codex/matches"')
  end

  it "shows the error pill when service signals 'not enough nodes'" do
    html = render_arena(left: nil, right: nil, pair_seed: nil, realm: realm,
                        error: "not enough nodes in realm")
    expect(html).to include("not enough nodes in realm")
    expect(html).to include("status-warning")
    expect(html).not_to include('name="winner_slug"')
  end

  it "uses gaia-* tokens only" do
    html = render_arena(left: left, right: right, pair_seed: "x" * 64, realm: realm)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end

  it "does not wire any Stimulus controller (plain forms, Turbo Frame handles response)" do
    html = render_arena(left: left, right: right, pair_seed: "x" * 64, realm: realm)
    expect(html).not_to include('data-controller=')
  end

  it "shows the realm_unknown fallback when realm is nil" do
    html = render_arena(left: nil, right: nil, pair_seed: nil, realm: nil, error: "no realm configured")
    expect(html).to include("Realm:")
    expect(html).to include("—")
  end
end

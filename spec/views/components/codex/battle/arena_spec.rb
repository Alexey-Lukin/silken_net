# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Battle::Arena, type: :view_component do
  let(:realm) { create(:codex_realm) }
  let(:left)  { create(:codex_node, realm: realm, attunement_elo: 1550, match_count: 4) }
  let(:right) { create(:codex_node, realm: realm, attunement_elo: 1450, match_count: 7) }

  def render_arena(**kwargs)
    # [ARCH.77] Справжній renderer — стаб замороженого маршрут-хелпера робив пін
    # твердженням про фікстуру, а не про роутер.
    render_component(**kwargs)
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
    expect(html).to include('action="/codex/matches"')
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

  it "renders the realm's name in the header when a realm is present" do
    html = render_arena(left: left, right: right, pair_seed: "x" * 64, realm: realm)
    expect(html).to include("Realm: #{realm.name_en}")
  end

  it "renders a skip form with pair_seed carried over and no winner_slug field" do
    html = render_arena(left: left, right: right, pair_seed: "abc123", realm: realm)
    expect(html).to include('name="skip"')
    expect(html).to include('value="true"')
    expect(html).to include('value="abc123"')
    expect(html).to include(">Skip<")
  end

  it "renders the error state even when left/right nodes are present (error takes precedence)" do
    html = render_arena(left: left, right: right, pair_seed: "x" * 64, realm: realm, error: "duplicate vote")
    expect(html).to include("duplicate vote")
    expect(html).to include("status-warning")
    expect(html).not_to include("Elo: 1550")
    expect(html).not_to include('name="winner_slug"')
  end

  it "wires focus-visible ring on the pick button for keyboard navigation" do
    html = render_arena(left: left, right: right, pair_seed: "x" * 64, realm: realm)
    expect(html).to include("focus-visible:ring-2")
    expect(html).to include("focus-visible:ring-gaia-primary")
  end
end

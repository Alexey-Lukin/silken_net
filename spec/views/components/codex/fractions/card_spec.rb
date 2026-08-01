# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::Card, type: :view_component do
  let(:realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let(:user)  { create(:user) }

  def render_card(fraction:, current_user:)
    # [ARCH.77] Справжній renderer знімає ВЕСЬ цей риштунок: стаб `render` існував
    # лише щоб протягнути `helpers` вкладеному `Cooldown` — у реальному контексті
    # Phlex робить це сам, а маршрут-хелпер більше не заморожений літералом.
    render_component(fraction: fraction, current_user: current_user)
  end

  it "renders the empty-state CTA when the user has no fraction" do
    html = render_card(fraction: nil, current_user: user)
    expect(html).to include("Choose a Fraction")
    expect(html).to include("/codex/fractions/picker")
    expect(html).to include("codex_fraction_card")
  end

  it "renders archetype, since-date, change CTA, and a Locked pill within cooldown" do
    fraction = create(:codex_fraction, user: user, node: node, archetype_key: "nlos_routing")
    html = render_card(fraction: fraction.reload, current_user: user)
    expect(html).to include("nlos_routing")
    expect(html).to include("Since")
    expect(html).to include("Change")
    expect(html).to include("Locked")
  end

  it "uses gaia-* tokens only — no raw bg-white / text-gray" do
    fraction = create(:codex_fraction, user: user, node: node)
    html = render_card(fraction: fraction.reload, current_user: user)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end
end

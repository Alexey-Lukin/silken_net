# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::Card, type: :view_component do
  let(:realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let(:user)  { create(:user) }

  def render_card(fraction:, current_user:)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_fraction_picker_path) { "/api/v1/codex/fractions/picker" }
      define_method(:render) do |component|
        if component.is_a?(Codex::Fractions::Cooldown)
          super(
            Class.new(Codex::Fractions::Cooldown) do
              define_method(:helpers) { helpers }
            end.new(fraction: component.instance_variable_get(:@fraction))
          )
        else
          super(component)
        end
      end
    end.new(fraction: fraction, current_user: current_user).call
  end

  it "renders the empty-state CTA when the user has no fraction" do
    html = render_card(fraction: nil, current_user: user)
    expect(html).to include("Choose a Fraction")
    expect(html).to include("/api/v1/codex/fractions/picker")
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

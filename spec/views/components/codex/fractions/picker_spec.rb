# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::Picker, type: :view_component do
  let(:realm) { create(:codex_realm) }
  let(:other_realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving, archetype_key: "nlos_routing") }
  let(:user)  { create(:user) }

  def render_picker(realms:, active_realm:, nodes:, current_fraction: nil)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_fractions_path) { "/api/v1/codex/fractions" }
      define_method(:api_v1_codex_fraction_picker_path) do |opts = {}|
        opts.empty? ? "/api/v1/codex/fractions/picker" : "/api/v1/codex/fractions/picker?realm=#{opts[:realm]}"
      end
    end.new(
      realms: realms, active_realm: active_realm, nodes: nodes,
      current_fraction: current_fraction
    ).call
  end

  it "renders header, realm tabs and node pick forms" do
    html = render_picker(
      realms: [ realm, other_realm ], active_realm: realm,
      nodes: [ node ], current_fraction: nil
    )
    expect(html).to include("Pick a Fraction")
    expect(html).to include(realm.name_en)
    expect(html).to include(other_realm.name_en)
    expect(html).to include(node.title_en)
    expect(html).to include('action="/api/v1/codex/fractions"')
    expect(html).to include('value="' + node.slug + '"')
    expect(html).to include('id="codex_fraction_picker"')
  end

  it "highlights the active realm tab with gaia-primary" do
    html = render_picker(realms: [ realm, other_realm ], active_realm: realm, nodes: [])
    expect(html).to include("bg-gaia-primary")
  end

  it "marks the current node as Current and skips the pick button" do
    fraction = create(:codex_fraction, user: user, node: node)
    html = render_picker(realms: [ realm ], active_realm: realm, nodes: [ node ],
                         current_fraction: fraction.reload)
    expect(html).to include("Current")
  end

  it "disables the pick button while cooldown is active on a different node" do
    other = create(:codex_node, realm: realm, lifecycle_status: :thriving)
    fraction = create(:codex_fraction, user: user, node: node) # within cooldown by default
    html = render_picker(realms: [ realm ], active_realm: realm, nodes: [ other ],
                         current_fraction: fraction.reload)
    expect(html).to include("disabled")
    expect(html).to include("Locked")
  end

  it "shows the empty-state copy when no nodes are pickable" do
    html = render_picker(realms: [ realm ], active_realm: realm, nodes: [])
    expect(html).to include("No pickable nodes")
  end

  it "uses gaia-* tokens only" do
    html = render_picker(realms: [ realm ], active_realm: realm, nodes: [ node ])
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Discoveries::List, type: :view_component do
  let(:user) { create(:user) }

  def render_list(**kwargs)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
    end.new(**kwargs).call
  end

  it "renders empty-state when discoveries.empty?" do
    html = render_list(discoveries: [], pagy: nil)
    expect(html).to include("Nothing unlocked yet")
    expect(html).to include("My Codex")
    expect(html).to include("Unlocked: 0")
  end

  it "renders one card per discovery with title + archetype + trigger" do
    n1 = create(:codex_node, title_en: "Yggdrasil", archetype_key: "planetary_regulator")
    n2 = create(:codex_node, title_en: "Mafusail",  archetype_key: "relict_oracle")
    d1 = create(:codex_discovery, user: user, node: n1, trigger_type: :match_milestone)
    d2 = create(:codex_discovery, user: user, node: n2, trigger_type: :telemetry_observation)
    html = render_list(discoveries: [ d1, d2 ], pagy: nil)
    expect(html).to include("Yggdrasil")
    expect(html).to include("planetary_regulator")
    expect(html).to include("Mafusail")
    expect(html).to include("match_milestone")
    expect(html).to include("Unlocked: 2")
  end

  it "uses gaia-* tokens only" do
    html = render_list(discoveries: [], pagy: nil)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end
end

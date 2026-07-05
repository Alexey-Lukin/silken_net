# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Discoveries::Toast, type: :view_component do
  let(:node) { create(:codex_node, title_en: "Mafusail", archetype_key: "relict_oracle") }

  def render_toast(**kwargs)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
    end.new(**kwargs).call
  end

  it "renders a Stimulus-wrapped toast with title, archetype, link" do
    html = render_toast(node: node, trigger_type: "match_milestone", unlocked_at: Time.utc(2026, 5, 9, 14, 30))
    expect(html).to include("Codex Unlocked")
    expect(html).to include("Mafusail")
    expect(html).to include("relict_oracle")
    expect(html).to include("Battle")
    expect(html).to include('data-controller="codex--reveal"')
    expect(html).to include("/api/v1/codex/nodes/#{node.slug}")
    expect(html).to include("14:30 UTC")
  end

  it "uses gaia-* tokens only" do
    html = render_toast(node: node, trigger_type: "telemetry_observation", unlocked_at: Time.current)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).to include("bg-gaia-surface")
  end

  it "labels each trigger_type" do
    %w[telemetry_observation match_milestone fraction_choice attunement_streak oracle_seasonal manual_unlock].each do |t|
      html = render_toast(node: node, trigger_type: t, unlocked_at: Time.current)
      expect(html).to match(/Observed|Battle|Pact|Streak|Oracle|Granted/)
    end
  end

  it "labels an unrecognized trigger_type with the default fallback" do
    html = render_toast(node: node, trigger_type: "some_future_trigger", unlocked_at: Time.current)
    expect(html).to include("Unlocked")
  end

  it "omits the unlocked timestamp from the meta line when unlocked_at is nil" do
    html = render_toast(node: node, trigger_type: "match_milestone", unlocked_at: nil)
    expect(html).to include(node.archetype_key)
    expect(html).not_to include("UTC")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::ProfileBadge do
  # ProfileBadge uses `api_v1_codex_fraction_picker_path` which requires
  # a Rails view context. We subclass + stub like other Codex component specs.
  def render_badge(fraction:)
    Class.new(described_class) do
      define_method(:api_v1_codex_fraction_picker_path) { "/api/v1/codex/fractions/picker" }
    end.new(fraction: fraction).call
  end

  def mock_fraction(archetype_key: "relict_oracle", cooldown_active: false)
    OpenStruct.new(
      archetype_key: archetype_key,
      cooldown_active?: cooldown_active,
      cooldown_until: Time.current + 7.days,
      seconds_until_unlocked: cooldown_active ? 7.days.to_i : 0
    )
  end

  describe "when fraction is present" do
    let(:html) { render_badge(fraction: mock_fraction) }

    it "renders the archetype_key label" do
      expect(html).to include("relict_oracle")
    end

    it "renders the 'Fraction' eyebrow label" do
      expect(html).to include("Fraction")
    end

    it "renders the Cooldown sub-component" do
      expect(html).to include("Open") # cooldown_active: false → Open pill
    end

    it "uses gaia-* tokens (no raw bg-white / text-gray)" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
      expect(html).not_to include("bg-white")
    end

    it "exposes the stable DOM id" do
      expect(html).to include('id="codex_fraction_profile_badge"')
    end
  end

  describe "when fraction is nil (empty state)" do
    let(:html) { render_badge(fraction: nil) }

    it "renders the 'Choose' CTA link pointing to the picker path" do
      expect(html).to include("Choose")
      expect(html).to include('href="/api/v1/codex/fractions/picker"')
    end

    it "applies focus-visible:ring-2 on the CTA link for a11y" do
      expect(html).to include("focus-visible:ring-2")
      expect(html).to include("focus-visible:ring-gaia-primary")
    end

    it "does NOT render the Cooldown sub-component" do
      expect(html).not_to include("Open")
      expect(html).not_to include("Locked")
    end
  end
end

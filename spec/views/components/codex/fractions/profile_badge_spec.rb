# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::ProfileBadge do
  # ProfileBadge uses `codex_fraction_picker_path` which requires
  # a Rails view context. We subclass + stub like other Codex component specs.
  def render_badge(fraction:)
    # [ARCH.77] Справжній renderer замість стабу маршрут-хелпера.
    render_component(fraction: fraction)
  end

  # Залишок вікна рахується в момент рендеру, а розряди формату — цілим
  # діленням, тож без заморозки часу мікросекунда, згаяна між побудовою
  # фікстури й читанням моделі, скидає цілий розряд донизу.
  around { |ex| freeze_time { ex.run } }

  # Стан cooldown'а виводиться з ОДНІЄЇ колонки `last_changed_at` (три
  # похідні: `cooldown_until`, `cooldown_active?`, `seconds_until_unlocked`),
  # тож фікстура задає лише залишок вікна й дає моделі вивести решту.
  def fraction_with(archetype_key: "relict_oracle", remaining: -1.hour)
    Codex::Fraction.new(
      archetype_key: archetype_key,
      last_changed_at: Time.current - Codex::Fraction::COOLDOWN + remaining
    )
  end

  describe "when fraction is present" do
    let(:html) { render_badge(fraction: fraction_with) }

    it "renders the archetype_key label" do
      expect(html).to include("relict_oracle")
    end

    it "renders the 'Fraction' eyebrow label" do
      expect(html).to include("Fraction")
    end

    it "renders the Cooldown sub-component" do
      expect(html).to include("Open")
    end

    it "passes THIS fraction down to the Cooldown pill" do
      # «Open» рендериться на будь-якому відкритому вікні, тож проводку
      # доводить лише залишок, унікальний для цієї фракції.
      locked = render_badge(fraction: fraction_with(remaining: 2.days + 9.hours))
      expect(locked).to include("Locked")
      expect(locked).to include("2d9h")
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
      expect(html).to include('href="/codex/fractions/picker"')
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

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::MobileNavToggle do
  let(:html) { render_component }

  describe "rendering" do
    it "renders a real <button> element (keyboard-activation semantics)" do
      expect(html).to start_with("<button")
    end

    it "is hidden on md+ viewports" do
      expect(html).to include("md:hidden")
    end

    it "registers itself as a mobile-nav#open click target" do
      expect(html).to include('data-action="click-&gt;mobile-nav#open"').or include('data-action="click->mobile-nav#open"')
    end

    it "controls the drawer via aria-controls" do
      expect(html).to include('aria-controls="mobile-nav-drawer"')
    end

    it "honours a custom target_id prop" do
      custom = render_component(target_id: "custom-drawer")
      expect(custom).to include('aria-controls="custom-drawer"')
    end

    it "starts collapsed (aria-expanded=false)" do
      expect(html).to include('aria-expanded="false"')
    end

    it "renders the burger icon SVG" do
      expect(html).to include("<svg")
      expect(html).to include('aria-hidden="true"')
    end
  end

  describe "i18n" do
    it "labels the trigger via I18n in Ukrainian" do
      I18n.with_locale(:uk) do
        expect(render_component).to include('aria-label="Відкрити навігацію"')
      end
    end

    it "switches the label to English under :en locale" do
      I18n.with_locale(:en) do
        expect(render_component).to include('aria-label="Open navigation"')
      end
    end
  end

  describe "design system compliance" do
    it "uses gaia tokens, not raw Tailwind colors" do
      expect(html).not_to include("bg-white")
      expect(html).not_to include("text-gray-")
    end

    it "uses gaia border + text tokens" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("text-gaia-text-muted")
    end

    it "uses focus-visible ring with the gaia primary token" do
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end
end

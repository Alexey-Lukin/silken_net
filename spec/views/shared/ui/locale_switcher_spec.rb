# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::LocaleSwitcher do
  describe "rendering" do
    let(:html) { render_component }

    it "renders a <form> that submits to api_v1_locale_path" do
      expect(html).to include('action="/api/v1/locale"')
      expect(html).to include('method="post"')
    end

    it "renders a native <select> element for locale choice" do
      expect(html).to include("<select")
      expect(html).to include('name="locale"')
    end

    it "auto-submits on change via onchange handler" do
      expect(html).to include("this.form.requestSubmit()")
    end

    it "no longer requires a Stimulus controller (native HTML select)" do
      expect(html).not_to include('data-controller="locale"')
    end

    it "renders one <option> per available locale" do
      I18n.available_locales.each do |locale|
        expect(html).to include("value=\"#{locale}\"")
      end
    end

    it "renders a noscript submit button as JS-off fallback" do
      expect(html).to include("<noscript>")
      expect(html).to include('type="submit"')
    end
  end

  describe "design system compliance" do
    let(:html) { render_component }

    it "uses gaia design tokens, not raw Tailwind colors" do
      expect(html).not_to include("bg-white")
      expect(html).not_to include("text-gray-900")
    end

    it "uses gaia border + surface tokens" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
    end

    it "uses focus-visible (not focus:) for keyboard rings" do
      expect(html).to include("focus-visible:")
    end

    it "uses custom text scale (text-tiny)" do
      expect(html).to include("text-tiny")
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "labels the switcher via aria-label" do
      expect(html).to include("aria-label")
    end

    it "provides a visually-hidden <label> for the select" do
      expect(html).to include("sr-only")
    end
  end

  describe "locale-aware initialization" do
    it "selects the explicit current_locale option" do
      html = render_component(current_locale: :en)
      # The <option> for EN should be selected
      expect(html).to include("EN · English")
    end

    it "falls back to I18n.locale when current_locale is nil" do
      I18n.with_locale(:uk) do
        html = render_component(current_locale: nil)
        expect(html).to include("UA · Українська")
      end
    end
  end
end

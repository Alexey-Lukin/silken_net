# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::LocaleSwitcher do
  describe "rendering" do
    let(:html) { render_component }

    it "renders a real <button> trigger that opens the popover" do
      expect(html).to include('popovertarget="locale-switcher-popover"')
      expect(html).to include('type="button"')
    end

    it "renders the popover as a <ul popover='auto'> for native light-dismiss" do
      expect(html).to include('popover="auto"')
      expect(html).to include('id="locale-switcher-popover"')
    end

    it "renders the popover with role=menu" do
      expect(html).to include('role="menu"')
    end

    it "no longer requires a Stimulus controller (native HTML Popover API)" do
      expect(html).not_to include('data-controller="locale"')
    end

    it "renders one form per available locale" do
      I18n.available_locales.each do |locale|
        expect(html).to include('name="locale"')
        expect(html).to include("value=\"#{locale}\"")
      end
    end

    it "submits to api_v1_locale_path" do
      expect(html).to include('action="/api/v1/locale"')
      expect(html).to include('method="post"')
    end

    it "marks the active locale with aria-current and disabled attribute" do
      I18n.with_locale(:uk) do
        html = render_component
        expect(html).to include('aria-current="true"')
        expect(html).to include('disabled="disabled"')
      end
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
      expect(html).to include("bg-gaia-surface-elevated")
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

    it "provides a screen-reader-only full locale name" do
      expect(html).to include("sr-only")
    end
  end

  describe "locale-aware initialization" do
    it "honours an explicit current_locale prop over I18n.locale" do
      html = render_component(current_locale: :en)
      expect(html).to include('aria-current="true"')
      expect(html).to include("EN · English")
    end

    it "falls back to I18n.locale when current_locale is nil" do
      I18n.with_locale(:uk) do
        html = render_component(current_locale: nil)
        expect(html).to include('aria-current="true"')
        expect(html).to include("UA · Українська")
      end
    end
  end
end

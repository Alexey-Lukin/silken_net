# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::ThemeSwitcher do
  describe "rendered HTML" do
    let(:html) { render_component }

    it "wraps in a div with data-controller=theme" do
      expect(html).to include('data-controller="theme"')
    end

    it "renders a toggle button with click->theme#toggle action" do
      expect(html).to include('data-action="click->theme#toggle"')
    end

    it "renders a button with data-theme-target=icon" do
      expect(html).to include('data-theme-target="icon"')
    end

    it "renders an SVG icon as default content" do
      expect(html).to include("<svg")
      expect(html).to include("</svg>")
    end

    it "includes id for turbo-permanent identification" do
      expect(html).to include('id="theme-switcher"')
    end

    it "includes data-turbo-permanent to persist across Turbo navigations" do
      expect(html).to include("data-turbo-permanent")
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "includes aria-label for the toggle button" do
      expect(html).to include("aria-label")
      expect(html).to include(I18n.t("theme.toggle_label"))
    end

    it "renders a button element" do
      expect(html).to include("<button")
    end
  end

  describe "styling" do
    let(:html) { render_component }

    it "uses gaia design system border token" do
      expect(html).to include("border-gaia-border")
    end

    it "uses transition-colors for smooth theme switching" do
      expect(html).to include("transition-colors")
    end
  end
end

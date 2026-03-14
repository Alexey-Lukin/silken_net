# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::Skeleton do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with default variant (:balance)" do
    let(:html) { render_component }

    it "renders a container with pulsing skeleton blocks" do
      expect(html).to include("animate-pulse")
    end

    it "renders three skeleton lines for the balance variant" do
      # balance variant has 3 lines: label, value, subtitle
      expect(html.scan("animate-pulse").length).to eq(3)
    end

    it "uses design system background for skeleton blocks" do
      expect(html).to include("bg-gaia-border")
    end

    it "wraps in a container with design system border and surface background" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
    end
  end

  describe "with :text variant" do
    let(:html) { render_component(variant: :text) }

    it "renders a single full-width skeleton line" do
      expect(html).to include("w-full")
      expect(html.scan("animate-pulse").length).to eq(1)
    end
  end

  describe "with :card variant" do
    let(:html) { render_component(variant: :card) }

    it "renders three skeleton lines for the card variant" do
      expect(html.scan("animate-pulse").length).to eq(3)
    end
  end

  describe "with custom lines count" do
    let(:html) { render_component(lines: 5) }

    it "renders the specified number of skeleton lines" do
      expect(html.scan("animate-pulse").length).to eq(5)
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "has role=status for screen readers" do
      expect(html).to include('role="status"')
    end

    it "has an aria-label indicating loading state" do
      expect(html).to include("Loading")
    end
  end

  describe "with additional classes" do
    let(:html) { render_component(class: "mt-8") }

    it "accepts extra CSS classes" do
      expect(html).to include("mt-8")
    end
  end
end

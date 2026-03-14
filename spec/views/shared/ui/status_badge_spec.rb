# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::StatusBadge do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "AASM state color mapping" do
    it "maps pending to yellow" do
      html = render_component(status: "pending")
      expect(html).to include("bg-yellow-900")
      expect(html).to include("text-yellow-200")
    end

    it "maps confirmed to green" do
      html = render_component(status: "confirmed")
      expect(html).to include("bg-emerald-800")
    end

    it "maps failed to red" do
      html = render_component(status: "failed")
      expect(html).to include("bg-red-900")
    end

    it "maps processing to amber with animation" do
      html = render_component(status: "processing")
      expect(html).to include("bg-amber-900")
      expect(html).to include("animate-pulse")
    end
  end

  describe "with an unknown status" do
    let(:html) { render_component(status: "unknown_state") }

    it "falls back to default styling" do
      expect(html).to include("bg-zinc-800")
      expect(html).to include("text-zinc-300")
    end
  end

  describe "status text rendering" do
    it "displays the status text" do
      html = render_component(status: "confirmed")
      expect(html).to include("confirmed")
    end

    it "accepts symbol statuses" do
      html = render_component(status: :pending)
      expect(html).to include("pending")
      expect(html).to include("bg-yellow-900")
    end
  end
end

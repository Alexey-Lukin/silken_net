# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::StatusBadge do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "AASM state color mapping" do
    it "maps pending to warning semantic token" do
      html = render_component(status: "pending")
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "maps confirmed to success semantic token" do
      html = render_component(status: "confirmed")
      expect(html).to include("bg-status-success")
    end

    it "maps failed to danger semantic token" do
      html = render_component(status: "failed")
      expect(html).to include("bg-status-danger")
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
      expect(html).to include("bg-status-neutral")
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
      expect(html).to include("bg-status-warning")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(status: "pending") }

    it "includes role=status" do
      expect(html).to include('role="status"')
    end

    it "includes aria-label with status text" do
      expect(html).to include("aria-label")
      expect(html).to include("Status: pending")
    end
  end
end

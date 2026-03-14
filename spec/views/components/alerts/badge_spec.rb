# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alerts::Badge do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  def mock_alert(severity: "medium", status: "active", id: 1)
    OpenStruct.new(id: id, severity: severity, status: status)
  end

  describe "severity styles" do
    it "renders low severity with zinc/gray style" do
      html = render_component(alert: mock_alert(severity: "low"))
      expect(html).to include("bg-zinc-800")
      expect(html).to include("text-zinc-300")
    end

    it "renders medium severity with warning style" do
      html = render_component(alert: mock_alert(severity: "medium"))
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "renders critical severity with red pulse" do
      html = render_component(alert: mock_alert(severity: "critical"))
      expect(html).to include("bg-red-900")
      expect(html).to include("text-red-200")
      expect(html).to include("animate-pulse")
    end

    it "falls back to zinc for unknown severity" do
      html = render_component(alert: mock_alert(severity: "unknown"))
      expect(html).to include("bg-zinc-800")
    end
  end

  describe "status styles" do
    it "renders resolved with opacity-50" do
      html = render_component(alert: mock_alert(status: "resolved"))
      expect(html).to include("opacity-50")
    end

    it "renders ignored with opacity-30 and line-through" do
      html = render_component(alert: mock_alert(status: "ignored"))
      expect(html).to include("opacity-30")
      expect(html).to include("line-through")
    end

    it "renders active with no extra opacity" do
      html = render_component(alert: mock_alert(status: "active"))
      expect(html).not_to include("opacity-")
      expect(html).not_to include("line-through")
    end
  end

  describe "rendering" do
    let(:html) { render_component(alert: mock_alert(severity: "critical", status: "active")) }

    it "displays severity and status text" do
      expect(html).to include("critical — active")
    end

    it "uses text-tiny for badge text" do
      expect(html).to include("text-tiny")
    end

    it "includes uppercase styling" do
      expect(html).to include("uppercase")
    end

    it "does not use arbitrary text sizes" do
      expect(html).not_to include("text-[")
    end

    it "includes the alert id in the element id" do
      expect(html).to include("alert_badge_1")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::StatCard do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with basic props" do
    let(:html) { render_component(label: "Active Trees", value: "12,847") }

    it "renders the label" do
      expect(html).to include("Active Trees")
    end

    it "renders the value" do
      expect(html).to include("12,847")
    end

    it "uses text-tiny for label instead of arbitrary text-[10px]" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[")
    end

    it "uses gap instead of space-x for flex layout" do
      expect(html).to include("gap-2")
      expect(html).not_to include("space-x")
    end

    it "does not include hardcoded margins in the label" do
      expect(html).not_to match(/mb-\d/)
    end
  end

  describe "with subtitle" do
    let(:html) { render_component(label: "Nodes", value: "500", sub: "online") }

    it "renders the subtitle" do
      expect(html).to include("online")
    end
  end

  describe "with danger mode" do
    let(:html) { render_component(label: "Alerts", value: "3", danger: true) }

    it "applies danger accent color to value" do
      expect(html).to include("text-status-danger-accent")
    end
  end

  describe "with class override" do
    let(:html) { render_component(label: "Test", value: "0", class: "mt-4") }

    it "accepts additional classes" do
      expect(html).to include("mt-4")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(label: "Trees", value: "100") }

    it "has role=group" do
      expect(html).to include('role="group"')
    end

    it "has aria-label matching the label" do
      expect(html).to include('aria-label="Trees"')
    end
  end
end

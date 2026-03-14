# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::EmptyState do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with title only" do
    let(:html) { render_component(title: "No records found.") }

    it "renders the title text" do
      expect(html).to include("No records found.")
    end

    it "renders the default icon" do
      expect(html).to include("○")
    end

    it "wraps in a div with dashed border" do
      expect(html).to include("border-dashed")
    end

    it "includes role=status for screen readers" do
      expect(html).to include('role="status"')
    end
  end

  describe "with description" do
    let(:html) { render_component(title: "Sensor is silent", description: "Check hardware connections.") }

    it "renders the description" do
      expect(html).to include("Check hardware connections.")
    end

    it "uses text-tiny instead of arbitrary text-[10px]" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[")
    end
  end

  describe "with custom icon" do
    let(:html) { render_component(title: "Empty", icon: "⚙") }

    it "renders the custom icon with aria-hidden" do
      expect(html).to include("⚙")
      expect(html).to include("aria-hidden")
    end
  end

  describe "with colspan for table rows" do
    let(:html) { render_component(title: "No data.", colspan: 5) }

    it "renders a table row with td spanning columns" do
      expect(html).to include("<tr>")
      expect(html).to include("colspan=\"5\"")
    end

    it "does not render the dashed border div" do
      expect(html).not_to include("border-dashed")
    end
  end
end

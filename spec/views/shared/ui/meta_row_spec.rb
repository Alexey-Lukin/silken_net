# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::MetaRow do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with basic props" do
    let(:html) { render_component(label: "Firmware", value: "v2.1.3") }

    it "renders the label with colon" do
      expect(html).to include("Firmware:")
    end

    it "renders the value" do
      expect(html).to include("v2.1.3")
    end

    it "uses gap instead of margin for spacing" do
      expect(html).to include("gap-2")
      expect(html).not_to include("ml-2")
    end
  end

  describe "with class override" do
    let(:html) { render_component(label: "Status", value: "OK", class: "border-b") }

    it "accepts additional classes" do
      expect(html).to include("border-b")
    end
  end

  describe "with non-string value" do
    let(:html) { render_component(label: "Count", value: 42) }

    it "converts value to string" do
      expect(html).to include("42")
    end
  end
end

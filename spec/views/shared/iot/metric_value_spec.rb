# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::IoT::MetricValue do # rubocop:disable RSpec/SpecFilePathFormat
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with a BigDecimal value" do
    let(:value) { BigDecimal("12.345678901234567890") }
    let(:html) { render_component(value: value) }

    it "displays only 4 decimal places" do
      expect(html).to include("12.3457")
    end

    it "includes the full precision in the title attribute" do
      expect(html).to include("title=\"12.34567890123456789\"")
    end
  end

  describe "with a float value" do
    let(:html) { render_component(value: 3.14159265358979) }

    it "displays 4 decimal places by default" do
      expect(html).to include("3.1416")
    end
  end

  describe "with custom precision" do
    let(:html) { render_component(value: 1.23456789, precision: 2) }

    it "uses the specified precision" do
      expect(html).to include("1.23")
    end
  end

  describe "with a unit" do
    let(:html) { render_component(value: 42.1234, unit: "σ") }

    it "displays the unit" do
      expect(html).to include("σ")
    end

    it "includes the unit in the title" do
      expect(html).to include("42.1234 σ")
    end
  end

  describe "with a nil value" do
    let(:html) { render_component(value: nil) }

    it "displays a dash" do
      expect(html).to include("—")
    end

    it "shows no data in the title" do
      expect(html).to include("No data")
    end
  end
end

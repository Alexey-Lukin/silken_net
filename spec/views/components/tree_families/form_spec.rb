# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Form do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_family(id: nil, name: nil, scientific_name: nil)
    family = TreeFamily.new(id: id, name: name, scientific_name: scientific_name)
    family.define_singleton_method(:persisted?) { id.present? }
    family.define_singleton_method(:to_key) { id ? [ id ] : nil }
    family
  end

  describe "form structure" do
    let(:html) { render_component(family: mock_family) }

    it "renders a form tag" do
      expect(html).to include("<form")
    end

    it "uses gaia design system surface classes" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
    end
  end

  describe "form labels (a11y)" do
    let(:html) { render_component(family: mock_family) }

    it "renders label tags associated with inputs" do
      expect(html).to include("<label")
      expect(html).to include("for=")
    end

    it "displays Species Identity label" do
      expect(html).to include("Species Identity")
    end

    it "displays Scientific Name label" do
      expect(html).to include("Scientific Name (Latin)")
    end

    it "displays all field labels" do
      expect(html).to include("Baseline Impedance")
      expect(html).to include("Critical Z Min")
      expect(html).to include("Critical Z Max")
      expect(html).to include("Sequestration Coefficient")
      expect(html).to include("Sap Flow Index")
      expect(html).to include("Bark Thickness")
    end
  end

  describe "form inputs" do
    let(:html) { render_component(family: mock_family) }

    it "includes text fields for name and scientific_name" do
      expect(html).to include('type="text"')
    end

    it "includes number fields for numeric attributes" do
      expect(html).to include('type="number"')
    end

    it "applies gaia input design tokens" do
      expect(html).to include("bg-gaia-input-bg")
      expect(html).to include("border-gaia-input-border")
    end

    it "includes focus-visible ring on inputs" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "submit button" do
    let(:html) { render_component(family: mock_family) }

    it "renders the submit button" do
      expect(html).to include("WRITE GENETIC CODE")
    end

    it "includes disabled opacity for accessibility" do
      expect(html).to include("disabled:opacity-50")
    end

    it "includes focus-visible ring for keyboard navigation" do
      expect(html).to include("focus-visible:ring-2")
    end

    it "uses gaia primary color tokens" do
      expect(html).to include("border-gaia-primary")
      expect(html).to include("text-gaia-primary")
    end
  end
end

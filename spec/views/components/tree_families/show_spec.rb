# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Show do

  def mock_family(id: 1, name: "Oak", scientific_name: "Quercus robur",
                  baseline_impedance: 45, carbon_sequestration_coefficient: 1.2,
                  critical_z_min: 10.0, critical_z_max: 80.0,
                  death_threshold_impedance: 5.0,
                  sap_flow_index: 0.7, bark_thickness: 12, foliage_density: 85,
                  fire_resistance_rating: "High")
    family = OpenStruct.new(
      id: id,
      name: name,
      scientific_name: scientific_name,
      baseline_impedance: baseline_impedance,
      carbon_sequestration_coefficient: carbon_sequestration_coefficient,
      critical_z_min: critical_z_min,
      critical_z_max: critical_z_max,
      death_threshold_impedance: death_threshold_impedance,
      sap_flow_index: sap_flow_index,
      bark_thickness: bark_thickness,
      foliage_density: foliage_density,
      fire_resistance_rating: fire_resistance_rating
    )
    family.define_singleton_method(:model_name) { ActiveModel::Name.new(TreeFamily) }
    family.define_singleton_method(:to_key) { [id] }
    family.define_singleton_method(:to_param) { id.to_s }
    family
  end

  let(:family) { mock_family }
  let(:html)   { render_component(family: family) }

  describe "hero section" do
    it "renders family name as heading" do
      expect(html).to include("Oak")
    end

    it "renders scientific name in italic" do
      expect(html).to include("Quercus robur")
    end

    it "renders baseline impedance" do
      expect(html).to include("45")
    end

    it "renders CO2 coefficient" do
      expect(html).to include("1.2")
    end

    it "does not render scientific name if absent" do
      family_no_sci = mock_family(scientific_name: nil)
      html = render_component(family: family_no_sci)
      expect(html).not_to include("Quercus robur")
    end
  end

  describe "threshold scale" do
    it "renders The Homeostasis Scale section" do
      expect(html).to include("The Homeostasis Scale")
    end

    it "renders BASELINE marker" do
      expect(html).to include("BASELINE")
    end

    it "renders SAFE_MIN marker" do
      expect(html).to include("SAFE_MIN")
    end

    it "renders SAFE_MAX marker" do
      expect(html).to include("SAFE_MAX")
    end

    it "renders DEATH marker" do
      expect(html).to include("DEATH")
    end
  end

  describe "biological properties table" do
    it "renders TinyML Biological Features heading" do
      expect(html).to include("TinyML Biological Features")
    end

    it "renders CO2 Sequestration row" do
      expect(html).to include("CO")
    end

    it "renders Sap Flow Index" do
      expect(html).to include("Sap Flow Index")
    end

    it "renders Bark Thickness with mm unit" do
      expect(html).to include("12 mm")
    end

    it "renders Foliage Density with percent" do
      expect(html).to include("85 %")
    end

    it "renders Fire Rating" do
      expect(html).to include("High")
    end
  end
end

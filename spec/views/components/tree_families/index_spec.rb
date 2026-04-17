# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Index do


  def mock_family(id: 1, name: "Oak", scientific_name: "Quercus robur", baseline_impedance: 45,
                  critical_z_min: 10, critical_z_max: 80, trees_count: 120)
    family = OpenStruct.new(
      id: id,
      name: name,
      scientific_name: scientific_name,
      baseline_impedance: baseline_impedance,
      critical_z_min: critical_z_min,
      critical_z_max: critical_z_max,
      trees_count: trees_count
    )
    family.define_singleton_method(:model_name) { ActiveModel::Name.new(TreeFamily) }
    family.define_singleton_method(:to_key) { [id] }
    family.define_singleton_method(:to_param) { id.to_s }
    family
  end

  let(:family)   { mock_family }
  let(:families) { [family, mock_family(id: 2, name: "Pine", scientific_name: "Pinus sylvestris", trees_count: 55)] }
  let(:html)     { render_component(families: families, pagy: mock_pagy(count: 63)) }

  describe "header" do
    it "renders Biological Matrix label" do
      expect(html).to include("Biological Matrix")
    end

    it "renders Global Species Constants heading" do
      expect(html).to include("Global Species Constants")
    end

    it "renders define new species link" do
      expect(html).to include("Define new tree species")
    end

    it "renders Define DNA button text" do
      expect(html).to include("+ Define DNA")
    end
  end

  describe "table headers" do
    it "renders Species Name column" do
      expect(html).to include("Species Name")
    end

    it "renders Baseline Z column" do
      expect(html).to include("Baseline Z")
    end

    it "renders Safe Range column" do
      expect(html).to include("Safe Range")
    end

    it "renders Population column" do
      expect(html).to include("Population")
    end
  end

  describe "family rows" do
    it "renders family name" do
      expect(html).to include("Oak")
    end

    it "renders scientific name" do
      expect(html).to include("Quercus robur")
    end

    it "renders baseline impedance with kΩ unit" do
      expect(html).to include("45 k")
    end

    it "renders safe range" do
      expect(html).to include("10 - 80")
    end

    it "renders tree count as Soldiers" do
      expect(html).to include("120 Soldiers")
    end

    it "renders AUDIT link with aria-label" do
      expect(html).to include("Audit Oak species")
    end

    it "renders EDIT link" do
      expect(html).to include("EDIT")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end
  end
end

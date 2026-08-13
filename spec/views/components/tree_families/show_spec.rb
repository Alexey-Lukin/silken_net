# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Show do
  # [TEST.12] Реальний запис замість `OpenStruct`. Мок брехав двічі: подавав
  # `fire_resistance_rating: "High"` при `numericality` (насправді це ПОРІГ у °C,
  # який `AlertDispatchService` звіряє з температурою телеметрії) і вигадував
  # метадані фреймворку (`model_name`/`to_key`/`to_param`), з яких Rails
  # виводить маршрут.
  def mock_family(id: 1, name: "Oak", scientific_name: "Quercus robur",
                  carbon_sequestration_coefficient: 1.2,
                  critical_z_min: 10.0, critical_z_max: 80.0,
                  sap_flow_index: 0.7, bark_thickness: 12, foliage_density: 85,
                  fire_resistance_rating: 60)
    build_stubbed(:tree_family,
                  id: id,
                  name: name,
                  scientific_name: scientific_name,
                  carbon_sequestration_coefficient: carbon_sequestration_coefficient,
                  critical_z_min: critical_z_min,
                  critical_z_max: critical_z_max,
                  sap_flow_index: sap_flow_index,
                  bark_thickness: bark_thickness,
                  foliage_density: foliage_density,
                  fire_resistance_rating: fire_resistance_rating)
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

    it "renders CO2 coefficient" do
      expect(html).to include("1.2")
    end

    it "does not render scientific name if absent" do
      family_no_sci = mock_family(scientific_name: nil)
      html = render_component(family: family_no_sci)
      expect(html).not_to include("Quercus robur")
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

    # [TEST.12] Значення несе ОДИНИЦЮ: це поріг у °C, який `AlertDispatchService`
    # звіряє з температурою телеметрії, а не якісний рейтинг. Без «°C» мітка
    # «Fire Rating» читалась як шкала, і сусідні рядки (mm, %) робили цю
    # відсутність ще помітнішою.
    it "renders Fire Rating with its temperature unit" do
      expect(html).to include("60 °C")
      expect(html).not_to include("High")
    end

    it "falls back to N/A when the threshold is unset" do
      rendered = render_component(family: mock_family(fire_resistance_rating: nil))
      expect(rendered).to include("N/A")
      expect(rendered).not_to include("°C")
    end
  end
end

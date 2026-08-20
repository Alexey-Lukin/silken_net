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
                  bark_thickness: 12, foliage_density: 85,
                  fire_resistance_rating: 60)
    build_stubbed(:tree_family,
                  id: id,
                  name: name,
                  scientific_name: scientific_name,
                  carbon_sequestration_coefficient: carbon_sequestration_coefficient,
                  critical_z_min: critical_z_min,
                  critical_z_max: critical_z_max,
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

    it "falls back to the unmeasured state when the threshold is unset" do
      rendered = render_component(family: mock_family(fire_resistance_rating: nil))
      expect(prop_value(rendered, "Fire Rating")).to eq(not_measured)
      expect(rendered).not_to include("°C")
    end
  end

  # [ARCH.84] Панель зветься «TinyML Biological Features», а `db/seeds.rb` жодної
  # з властивостей не пише — тобто фабриковані числа бачила КОЖНА порода.
  # (`sap_flow_index`, що колись множив pest-поріг, знято цілком — [ARCH.102] ⚖️
  # 08-20; урок про фабрикований нуль лишається на вцілілих полях.)
  describe "properties that were never measured" do
    let(:bare) do
      mock_family(bark_thickness: nil,
                  foliage_density: nil, fire_resistance_rating: nil)
    end

    it "names the unmeasured state instead of printing a fabricated zero" do
      rendered = render_component(family: bare)

      expect(prop_value(rendered, "Bark Thickness")).to eq(not_measured)
      expect(prop_value(rendered, "Foliage Density")).to eq(not_measured)
      expect(prop_value(rendered, "Fire Rating")).to eq(not_measured)
    end

    # ⊥ Ліхтар: без нього «не виміряно» не відрізнити від «завжди не виміряно»,
    # і нуль тут ДОСЯЖНИЙ (валідація нуль приймає).
    it "still prints a measured zero as a number" do
      rendered = render_component(
        family: mock_family(bark_thickness: 0, foliage_density: 0)
      )

      expect(prop_value(rendered, "Bark Thickness")).to eq("0 mm")
      expect(prop_value(rendered, "Foliage Density")).to eq("0 %")
    end
  end

  # [ARCH.84] Значення живе в СУСІДНЬОМУ `<span>` за міткою; пін на текст усього
  # документа проходив би через будь-який інший рядок таблиці (§Guard-craft #17).
  def prop_value(rendered, label)
    Nokogiri::HTML5.fragment(rendered)
      .css("span")
      .find { |span| span.text.strip == label }
      &.next_element&.text&.strip
  end

  def not_measured
    I18n.t("ui.measurement.not_measured")
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.36] Стеля — те, що друкує HTML. Кожен приклад несе обидві половини: перелічене Є,
# а блоб і ключ, якого не друкує жодна сторінка, ВІДСУТНІ — поодинці кожна зелена при зламаній парі.
RSpec.describe TreeFamilyBlueprint, type: :model do
  let(:family) do
    build(:tree_family, id: 11, name: "Scots Pine", scientific_name: "Pinus sylvestris",
                        carbon_sequestration_coefficient: 0.8, trees_count: 4,
                        biological_properties: { "bark_thickness" => 12, "foliage_density" => 0.6,
                                                 "fire_resistance_rating" => 55, "sap_flow_index" => 0.3 })
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(family, view: :index)) }

    it "carries exactly what the index page prints" do
      expect(parsed).to eq("id" => 11, "name" => "Scots Pine",
                           "scientific_name" => "Pinus sylvestris", "trees_count" => 4)
    end
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(family, view: :show)) }

    it "carries the show page's fields through the declared accessors, never the blob" do
      expect(parsed).to include("name" => "Scots Pine", "carbon_sequestration_coefficient" => 0.8,
                                "bark_thickness" => 12, "foliage_density" => 0.6,
                                "fire_resistance_rating" => 55)
      expect(parsed).not_to have_key("biological_properties")
      expect(parsed.to_s).not_to include("sap_flow_index")
    end
  end
end

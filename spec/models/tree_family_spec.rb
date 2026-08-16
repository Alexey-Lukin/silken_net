# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamily, type: :model do
  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "has many trees with restrict_with_error" do
      association = described_class.reflect_on_association(:trees)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:restrict_with_error)
    end

    it "prevents deletion when trees exist" do
      family = create(:tree_family)
      create(:tree, tree_family: family)

      expect { family.destroy }.not_to change(described_class, :count)
      expect(family.errors[:base]).to be_present
    end

    it "allows deletion when no trees exist" do
      family = create(:tree_family)

      expect { family.destroy }.to change(described_class, :count).by(-1)
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    subject { build(:tree_family) }

    describe "name" do
      it "requires presence" do
        family = build(:tree_family, name: nil)
        expect(family).not_to be_valid
        expect(family.errors[:name]).to include("can't be blank")
      end

      it "requires uniqueness" do
        create(:tree_family, name: "Oak")
        duplicate = build(:tree_family, name: "Oak")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end
    end

    describe "scientific_name" do
      it "allows nil" do
        family = build(:tree_family, scientific_name: nil)
        expect(family).to be_valid
      end

      it "allows unique values" do
        family = build(:tree_family, scientific_name: "Quercus robur")
        expect(family).to be_valid
      end

      it "requires uniqueness when present" do
        create(:tree_family, scientific_name: "Quercus robur")
        duplicate = build(:tree_family, scientific_name: "Quercus robur")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:scientific_name]).to include("has already been taken")
      end

      it "allows multiple nil values (partial unique index)" do
        create(:tree_family, scientific_name: nil)
        second = build(:tree_family, scientific_name: nil)
        expect(second).to be_valid
      end
    end

    describe "critical_z_min" do
      it "requires presence" do
        family = build(:tree_family, critical_z_min: nil)
        expect(family).not_to be_valid
      end

      it "requires numericality" do
        family = build(:tree_family, critical_z_min: "abc")
        expect(family).not_to be_valid
      end
    end

    describe "critical_z_max" do
      it "requires presence" do
        family = build(:tree_family, critical_z_max: nil)
        expect(family).not_to be_valid
      end

      it "requires numericality" do
        family = build(:tree_family, critical_z_max: "abc")
        expect(family).not_to be_valid
      end

      it "must be greater than critical_z_min" do
        family = build(:tree_family, critical_z_min: 10.0, critical_z_max: 5.0)
        expect(family).not_to be_valid
        expect(family.errors[:critical_z_max]).to be_present
      end

      it "cannot equal critical_z_min" do
        family = build(:tree_family, critical_z_min: 10.0, critical_z_max: 10.0)
        expect(family).not_to be_valid
      end

      it "accepts values greater than critical_z_min" do
        family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
        expect(family).to be_valid
      end
    end

    describe "carbon_sequestration_coefficient" do
      it "requires a positive value" do
        family = build(:tree_family, carbon_sequestration_coefficient: 0)
        expect(family).not_to be_valid
        expect(family.errors[:carbon_sequestration_coefficient]).to be_present
      end

      it "rejects negative values" do
        family = build(:tree_family, carbon_sequestration_coefficient: -1.0)
        expect(family).not_to be_valid
      end

      it "accepts positive float values" do
        family = build(:tree_family, carbon_sequestration_coefficient: 1.5)
        expect(family).to be_valid
      end

      it "defaults to 1.0" do
        family = described_class.new
        expect(family.carbon_sequestration_coefficient).to eq(1.0)
      end
    end

    describe "JSONB biological_properties" do
      it "allows nil for sap_flow_index" do
        family = build(:tree_family, sap_flow_index: nil)
        expect(family).to be_valid
      end

      it "validates sap_flow_index numericality when present" do
        family = build(:tree_family, sap_flow_index: "abc")
        expect(family).not_to be_valid
      end

      it "allows nil for bark_thickness" do
        family = build(:tree_family, bark_thickness: nil)
        expect(family).to be_valid
      end

      it "validates bark_thickness numericality when present" do
        family = build(:tree_family, bark_thickness: "not_a_number")
        expect(family).not_to be_valid
      end

      it "allows nil for foliage_density" do
        family = build(:tree_family, foliage_density: nil)
        expect(family).to be_valid
      end

      it "validates foliage_density numericality when present" do
        family = build(:tree_family, foliage_density: "bad")
        expect(family).not_to be_valid
      end

      it "allows nil for fire_resistance_rating" do
        family = build(:tree_family, fire_resistance_rating: nil)
        expect(family).to be_valid
      end

      it "validates fire_resistance_rating numericality when present" do
        family = build(:tree_family, fire_resistance_rating: "high")
        expect(family).not_to be_valid
      end

      it "accepts valid numeric values for all JSONB properties" do
        family = build(:tree_family,
                       sap_flow_index: 0.75,
                       bark_thickness: 12.5,
                       foliage_density: 85.0,
                       fire_resistance_rating: 3)
        expect(family).to be_valid
      end

      # [ARCH.84] Кожен приклад вище подає ЧИСЛО — тобто те, чого форма не шле
      # ніколи. `store_accessor` кладе в JSONB рівно вантаж форми, а вантаж
      # HTML-форми це РЯДОК, і `AlertDispatchService` ним арифметичить:
      # виміряно рантаймом `DEFAULT_PEST_THRESHOLD * "0.7"` → `TypeError`,
      # `temperature_c >= "60"` → `ArgumentError`. Тож питання тут не про
      # валідність, а про ТИП того, що осіло.
      describe "the shape an HTML form actually writes" do
        it "stores a numeric string as a number" do
          family = create(:tree_family, sap_flow_index: "0.7", bark_thickness: "12")
          family.reload

          expect(family.sap_flow_index).to be_a(Numeric)
          expect(family.sap_flow_index.to_f).to eq(0.7)
          expect(family.bark_thickness).to be_a(Numeric)
          expect(family.bark_thickness.to_i).to eq(12)
        end

        it "drops a blank string so an optional property stays optional" do
          family = build(:tree_family, sap_flow_index: "", fire_resistance_rating: "")

          expect(family).to be_valid
          expect(family.sap_flow_index).to be_nil
          expect(family.fire_resistance_rating).to be_nil
        end

        # ⊥ Ліхтар до обох: нечисловий рядок мусить ЛИШИТИСЬ рядком. `to_f` тут
        # був би найгіршим можливим ліком — «abc» стало б `0.0`, тобто невалідне
        # зробилось би валідним, а поріг шкідників — нулем.
        it "leaves a non-numeric string alone so numericality still reports it" do
          family = build(:tree_family, sap_flow_index: "abc")

          expect(family).not_to be_valid
          expect(family.sap_flow_index).to eq("abc")
        end
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".alphabetical" do
      it "orders by name ascending" do
        _zebra = create(:tree_family, name: "Zebra Wood")
        _ash = create(:tree_family, name: "Ash")
        _maple = create(:tree_family, name: "Maple")

        names = described_class.alphabetical.pluck(:name)
        expect(names).to eq([ "Ash", "Maple", "Zebra Wood" ])
      end
    end
  end

  # =========================================================================
  # METHODS
  # =========================================================================
  describe "#display_name" do
    it "returns just the name when scientific_name is nil" do
      family = build(:tree_family, name: "Дуб звичайний", scientific_name: nil)
      expect(family.display_name).to eq("Дуб звичайний")
    end

    it "returns scientific_name with name in parentheses when scientific_name is present" do
      family = build(:tree_family, name: "Дуб звичайний", scientific_name: "Quercus robur")
      expect(family.display_name).to eq("Quercus robur (Дуб звичайний)")
    end

    it "returns just the name when scientific_name is empty string" do
      family = build(:tree_family, name: "Pine", scientific_name: "")
      expect(family.display_name).to eq("Pine")
    end
  end

  describe "#weighted_growth_points" do
    it "multiplies raw points by carbon_sequestration_coefficient" do
      family = build(:tree_family, carbon_sequestration_coefficient: 1.5)
      expect(family.weighted_growth_points(10)).to eq(15.0)
    end

    it "returns raw points when coefficient is 1.0" do
      family = build(:tree_family, carbon_sequestration_coefficient: 1.0)
      expect(family.weighted_growth_points(10)).to eq(10.0)
    end

    it "reduces points for species with lower coefficient" do
      family = build(:tree_family, carbon_sequestration_coefficient: 0.8)
      expect(family.weighted_growth_points(10)).to eq(8.0)
    end

    it "rounds to 2 decimal places" do
      family = build(:tree_family, carbon_sequestration_coefficient: 1.3)
      expect(family.weighted_growth_points(7)).to eq(9.1)
    end

    it "handles zero raw points" do
      family = build(:tree_family, carbon_sequestration_coefficient: 1.5)
      expect(family.weighted_growth_points(0)).to eq(0.0)
    end

    it "handles negative raw points (sensor anomaly pass-through)" do
      family = build(:tree_family, carbon_sequestration_coefficient: 1.5)
      expect(family.weighted_growth_points(-5)).to eq(-7.5)
    end
  end

  describe "#healthy_z?" do
    let(:family) { build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0) }

    it "returns true for a value within bounds" do
      expect(family.healthy_z?(25.0)).to be true
    end

    it "returns true at the lower boundary" do
      expect(family.healthy_z?(5.0)).to be true
    end

    it "returns true at the upper boundary" do
      expect(family.healthy_z?(45.0)).to be true
    end

    it "returns false below the lower boundary" do
      expect(family.healthy_z?(4.9)).to be false
    end

    it "returns false above the upper boundary" do
      expect(family.healthy_z?(45.1)).to be false
    end

    it "converts string values to float" do
      expect(family.healthy_z?("25.0")).to be true
    end
  end

  # =========================================================================
  # FACTORY TRAITS
  # =========================================================================
  describe "factory traits" do
    it "creates a valid default tree_family" do
      expect(build(:tree_family)).to be_valid
    end

    it "creates a valid scots_pine" do
      family = build(:tree_family, :scots_pine)
      expect(family).to be_valid
      expect(family.name).to eq("Scots Pine")
      expect(family.scientific_name).to eq("Pinus sylvestris")
      expect(family.carbon_sequestration_coefficient).to eq(0.8)
    end

    it "creates a valid common_oak" do
      family = build(:tree_family, :common_oak)
      expect(family).to be_valid
      expect(family.name).to eq("Common Oak")
      expect(family.scientific_name).to eq("Quercus robur")
      expect(family.carbon_sequestration_coefficient).to eq(1.5)
    end
  end

  # =========================================================================
  # STORE ACCESSORS
  # =========================================================================
  describe "store_accessor :biological_properties" do
    it "stores and retrieves sap_flow_index" do
      family = create(:tree_family, sap_flow_index: 0.75)
      expect(family.reload.sap_flow_index).to eq(0.75)
    end

    it "stores and retrieves bark_thickness" do
      family = create(:tree_family, bark_thickness: 12.5)
      expect(family.reload.bark_thickness).to eq(12.5)
    end

    it "stores and retrieves foliage_density" do
      family = create(:tree_family, foliage_density: 85.0)
      expect(family.reload.foliage_density).to eq(85.0)
    end

    it "stores and retrieves fire_resistance_rating" do
      family = create(:tree_family, fire_resistance_rating: 3)
      expect(family.reload.fire_resistance_rating).to eq(3)
    end

    it "stores all properties in the biological_properties JSON column" do
      family = create(:tree_family,
                      sap_flow_index: 0.75,
                      bark_thickness: 12.5,
                      foliage_density: 85.0,
                      fire_resistance_rating: 3)
      family.reload
      expect(family.biological_properties).to include(
        "sap_flow_index" => 0.75,
        "bark_thickness" => 12.5,
        "foliage_density" => 85.0,
        "fire_resistance_rating" => 3
      )
    end
  end
end

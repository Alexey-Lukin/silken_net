class AddScientificNameAndCarbonCoefficientToTreeFamilies < ActiveRecord::Migration[8.1]
  def change
    add_column :tree_families, :scientific_name, :string
    add_column :tree_families, :carbon_sequestration_coefficient, :float, default: 1.0, null: false

    add_index :tree_families, :scientific_name, unique: true, where: "scientific_name IS NOT NULL"
  end
end

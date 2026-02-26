class RenameBaseResistanceToBaselineImpedanceInTreeFamilies < ActiveRecord::Migration[8.1]
  def change
    rename_column :tree_families, :base_resistance, :baseline_impedance
  end
end

# frozen_string_literal: true

# rails generate migration AddBiomassFieldsToMaintenanceRecords biomass_yield_kg:decimal biomass_passport_tx_hash:string
#
# Afterlife Economy (Puro.earth Integration):
# When a tree dies, the forester extracts dead wood and records a biomass_extraction
# MaintenanceRecord. These columns store the D-MRV (Digital Measurement, Reporting
# and Verification) payload for Biochar CORC generation on Puro.earth.
class AddBiomassFieldsToMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_records, :biomass_yield_kg, :decimal, precision: 10, scale: 2
    add_column :maintenance_records, :biomass_passport_tx_hash, :string
  end
end

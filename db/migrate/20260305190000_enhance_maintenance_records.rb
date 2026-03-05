# frozen_string_literal: true

# OpEx-метрики (Financial Gap): labor_hours + parts_cost для unit-економіки Series C
# Hardware State Sync: hardware_verified — підтвердження патрульним після STM32-пульсу
# Координати втручання: latitude + longitude GPS телефону патрульного (захист від "диванного ремонту")
class EnhanceMaintenanceRecords < ActiveRecord::Migration[8.1]
  def change
    # --- OpEx Financial Tracking ---
    add_column :maintenance_records, :labor_hours, :decimal, precision: 8, scale: 2
    add_column :maintenance_records, :parts_cost,  :decimal, precision: 10, scale: 2

    # --- Hardware State Sync ---
    add_column :maintenance_records, :hardware_verified, :boolean, default: false, null: false

    # --- Intervention Coordinates (anti-sofa-repair) ---
    add_column :maintenance_records, :latitude,  :decimal, precision: 10, scale: 6
    add_column :maintenance_records, :longitude, :decimal, precision: 10, scale: 6

    add_index :maintenance_records, :hardware_verified
    add_index :maintenance_records, :action_type
  end
end

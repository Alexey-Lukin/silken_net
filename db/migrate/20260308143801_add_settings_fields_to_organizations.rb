# frozen_string_literal: true

# Додаємо поля для налаштування порогів тривоги та чутливості AI
# на рівні Організації (The Brain Map).
class AddSettingsFieldsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :alert_threshold_critical_z, :decimal, precision: 5, scale: 2, default: 2.5
    add_column :organizations, :ai_sensitivity, :decimal, precision: 3, scale: 2, default: 0.7
  end
end

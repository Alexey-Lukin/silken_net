class AddSafetyEnvelopeAndEnergyBudgetToActuators < ActiveRecord::Migration[8.1]
  def change
    add_column :actuators, :max_active_duration_s, :integer
    add_column :actuators, :estimated_mj_per_action, :decimal
  end
end

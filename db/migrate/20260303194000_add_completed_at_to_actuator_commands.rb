# frozen_string_literal: true

class AddCompletedAtToActuatorCommands < ActiveRecord::Migration[8.0]
  def change
    add_column :actuator_commands, :completed_at, :datetime
  end
end

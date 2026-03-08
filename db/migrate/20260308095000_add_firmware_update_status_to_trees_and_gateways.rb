# frozen_string_literal: true

class AddFirmwareUpdateStatusToTreesAndGateways < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :firmware_update_status, :integer, default: 0, null: false
    add_column :gateways, :firmware_update_status, :integer, default: 0, null: false
  end
end

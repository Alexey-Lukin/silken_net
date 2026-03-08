# frozen_string_literal: true

class AddCompatibleHardwareVersionsToBioContractFirmwares < ActiveRecord::Migration[8.1]
  def change
    add_column :bio_contract_firmwares, :compatible_hardware_versions, :jsonb, default: [], null: false
  end
end

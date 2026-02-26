class CreateBioContractFirmwares < ActiveRecord::Migration[8.1]
  def change
    create_table :bio_contract_firmwares do |t|
      t.string :version
      t.text :binary_payload
      t.boolean :is_active

      t.timestamps
    end
  end
end

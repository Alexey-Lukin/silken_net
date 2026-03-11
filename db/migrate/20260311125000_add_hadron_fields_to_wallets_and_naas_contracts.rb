class AddHadronFieldsToWalletsAndNaasContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :hadron_kyc_status, :string, default: "pending"
    add_index :wallets, :hadron_kyc_status

    add_column :naas_contracts, :hadron_asset_id, :string
    add_index :naas_contracts, :hadron_asset_id
  end
end

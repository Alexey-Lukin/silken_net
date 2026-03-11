class AddSolanaAddressToWalletsAndOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :solana_public_address, :string
    add_column :organizations, :solana_public_address, :string
  end
end

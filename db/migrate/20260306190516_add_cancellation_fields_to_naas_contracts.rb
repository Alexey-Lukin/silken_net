class AddCancellationFieldsToNaasContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :naas_contracts, :cancellation_terms, :jsonb, default: {}
    add_column :naas_contracts, :cancelled_at, :datetime
  end
end

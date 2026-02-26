class AddBillingEmailToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :billing_email, :string
  end
end

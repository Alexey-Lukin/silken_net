class AddPaidAtToParametricInsurances < ActiveRecord::Migration[8.1]
  def change
    add_column :parametric_insurances, :paid_at, :datetime
  end
end
